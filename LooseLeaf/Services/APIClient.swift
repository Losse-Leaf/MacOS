import Foundation
import os

public extension Notification.Name {
    static let looseLeafUnauthorized = Notification.Name("com.looseleaf.archive.unauthorized")
}

/// API 请求错误定义（严禁静默吞错）
public enum APIError: LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case unauthorized(String)
    case notModified
    case serverError(code: Int, message: String)
    case networkFailure(String)
    case decodingFailure(String)
    /// 对象存储直传错误（与中枢业务错误区分：4xx 为永久错误，不应重试）
    case storageError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "无效的接口地址: \(path)"
        case .unauthorized(let msg):
            return msg.isEmpty ? "设备凭据未授权或已失效，请重新完成配对或验证主理人密钥" : msg
        case .notModified:
            return "数据未变更 (304)"
        case .serverError(_, let msg):
            return msg
        case .networkFailure(let detail):
            return "网络连接异常: \(detail)"
        case .decodingFailure(let detail):
            return "响应数据解析失败: \(detail)"
        case .storageError(_, let msg):
            return "对象存储直传失败: \(msg)"
        }
    }
}

/// RESTful API v1 异步网络客户端
/// 对接 Go 后端数据中枢，支持 ETag / 304 缓存协商与受信任设备子钥匙鉴权
public actor APIClient {
    public static let shared = APIClient()
    public static let hubURLDefaultsKey = "looseleaf_hub_base_url"

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "api")

    /// JSON 编解码器实例
    ///
    /// 关键：**不能跨任务复用**。`JSONDecoder` 不是线程安全的 ——
    /// 同一个实例被两个并发解码同时使用会破坏内部状态，
    /// 表现为偶发的「数据解析失败」。本文件里上传路径已经改成
    /// 「每次新建局部 decoder」（注释明确写了「不能复用 static decoder」），
    /// 而普通请求路径却还在复用 —— 同一份文件里两套相反的做法。
    /// 现在统一为**每次新建**（一次 JSONDecoder 的构造成本远低于竞态风险）。
    private static func makeDecoder() -> JSONDecoder { JSONDecoder() }
    private static func makeEncoder() -> JSONEncoder { JSONEncoder() }

    private let session: URLSession
    /// ETag 缓存：URL → (设备令牌指纹, ETag)
    /// 必须与令牌绑定 —— 换令牌后沿用旧 ETag 会让服务端回 304，导致数据静默不更新。
    private var etagCache: [String: (token: String, etag: String)] = [:]
    /// 401 只广播一次，避免并发请求同时 401 时反复写盘与刷屏
    private var hasNotifiedUnauthorized: Bool = false

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 120
            config.waitsForConnectivity = true
            config.httpMaximumConnectionsPerHost = 8
            config.requestCachePolicy = .useProtocolCachePolicy
            // 关键：不能用相对 diskPath。相对路径会落到进程当前工作目录：
            // 开发时污染仓库，Finder 启动时 CWD 通常是 "/"，导致缓存库无法创建，
            // 每次请求都退化到无缓存（日志里可见 Cache.db Error=14）。
            if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let httpCacheDirectory = caches.appendingPathComponent("LooseLeaf/HTTPCache", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: httpCacheDirectory, withIntermediateDirectories: true)
                    config.urlCache = URLCache(
                        memoryCapacity: 8 * 1024 * 1024,
                        diskCapacity: 64 * 1024 * 1024,
                        directory: httpCacheDirectory
                    )
                } catch {
                    // 目录不可写（受限环境/只读容器）时退化为纯内存缓存，
                    // 否则 URLCache 会持续报 Cache.db Error=14，且每次请求都无缓存。
                    config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0)
                }
            } else {
                config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0)
            }
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Hub 地址与媒体路径解析

    /// 中枢地址缓存：避免每次请求都跨进程读取 UserDefaults
    nonisolated(unsafe) private static var cachedBaseURL: String = ""

    public nonisolated var baseURLString: String {
        if !Self.cachedBaseURL.isEmpty {
            return Self.cachedBaseURL
        }
        let saved = UserDefaults.standard.string(forKey: Self.hubURLDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved: String
        if saved.isEmpty {
            resolved = "http://localhost:8088"
        } else {
            resolved = saved.hasSuffix("/") ? String(saved.dropLast()) : saved
        }
        Self.cachedBaseURL = resolved
        return resolved
    }

    public nonisolated func setBaseURL(_ urlString: String) {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        let previous = UserDefaults.standard.string(forKey: Self.hubURLDefaultsKey) ?? ""
        UserDefaults.standard.set(cleaned, forKey: Self.hubURLDefaultsKey)
        Self.cachedBaseURL = cleaned
        if !previous.isEmpty, previous != cleaned {
            // 换中枢后旧设备令牌对新节点无效；继续携带只会让配对/探针请求 401
            CredentialStore.deleteToken()
            // ETag 必须随中枢一起失效：旧节点的 ETag 发往新节点会换来 304，导致拉不到任何数据
            Task { await APIClient.shared.invalidateCaches() }
        }
    }

    /// 清空 ETag 等协商缓存（换中枢 / 重新配对 / 手动强制刷新后调用）
    public func invalidateCaches() {
        etagCache.removeAll()
        hasNotifiedUnauthorized = false
    }

    /// 将后端返回的相对媒体路径 (如 /media/...) 补全为可访问的完整 URL。
    /// 文件名可能含空格/中文/#，必须做路径转义，否则 URL(string:) 直接返回 nil（图片静默不显示）。
    public nonisolated func resolveMediaURL(_ rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let url = URL(string: trimmed) { return url }
            let allowed = CharacterSet.urlFragmentAllowed.union(CharacterSet(charactersIn: "%"))
            return URL(string: trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }
        let prefix = baseURLString
        let path = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "?&=%+"))
        let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return URL(string: "\(prefix)\(encoded)")
    }

    /// 单个路径段转义（id / 城市码 / 备份文件名）
    private nonisolated func escapePathComponent(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    // MARK: - 通用请求构建与执行

    private func buildRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        bodyData: Data? = nil,
        contentType: String = "application/json",
        useETag: Bool = false,
        timeout: TimeInterval = 30
    ) throws -> (URLRequest, String) {
        let base = baseURLString
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard var components = URLComponents(string: "\(base)\(normalizedPath)") else {
            throw APIError.invalidURL("\(base)\(normalizedPath)")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL(path)
        }

        let cacheKey = url.absoluteString
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        // 关键：Content-Type 必须**无条件**设置。
        // 原先它被放在 `if let bodyData` 里，而 multipart 上传走的是
        // `upload(for:fromFile:)`（httpBody 为 nil），于是 boundary 从未发给后端，
        // 后端解析不出 file 字段 —— 表现为「图片怎么都传不上去」。
        if let bodyData {
            request.httpBody = bodyData
        }
        if !contentType.isEmpty {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        if let token = CredentialStore.getToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Device-Token")
        }

        // ETag 必须与当前设备令牌匹配：换了令牌（重新配对）后旧 ETag 会让服务端回 304
        if useETag, method == "GET",
           let cached = etagCache[cacheKey],
           cached.token == (CredentialStore.getToken() ?? "") {
            request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        return (request, cacheKey)
    }

    /// 仅对幂等 GET 做一次轻量重试；POST/PUT/DELETE 绝不自动重放。
    /// 重试必须尊重取消信号：取消后不得再发请求，且退避需指数化 + 抖动以避免多端惊群。
    private func dataWithRetry(for request: URLRequest, attempts: Int) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<max(1, attempts) {
            do {
                return try await session.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    let delay = pow(2.0, Double(attempt)) * 0.35 + Double.random(in: 0...0.2)
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }
        throw APIError.networkFailure(lastError?.localizedDescription ?? "网络请求失败")
    }

    private func performEnvelopeRequest<T: Decodable & Sendable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        useETag: Bool = false
    ) async throws -> T {
        let bodyData: Data?
        if let body {
            bodyData = try Self.makeEncoder().encode(body)
        } else {
            bodyData = nil
        }

        let (request, cacheKey) = try buildRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData,
            useETag: useETag
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataWithRetry(for: request, attempts: method == "GET" ? 2 : 1)
        } catch {
            throw APIError.networkFailure(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkFailure("无效的 HTTP 响应")
        }

        if http.statusCode == 304 {
            throw APIError.notModified
        }

        if http.statusCode == 401 {
            let errEnvelope = try? Self.makeDecoder().decode(APIEnvelope<EmptyPayload>.self, from: data)
            Self.logger.warning("Received 401 unauthorized from \(path, privacy: .public)")
            if !hasNotifiedUnauthorized {
                hasNotifiedUnauthorized = true
                NotificationCenter.default.post(name: .looseLeafUnauthorized, object: nil)
            }
            throw APIError.unauthorized(errEnvelope?.message ?? "")
        }

        // 关键：ETag 只在确认 2xx 之后写入。
        // 若在状态码校验之前写入，服务端 5xx 附带的错误 ETag 会覆盖正确值，
        // 下次请求带上错误 If-None-Match 可能换来 304 —— 客户端会认为「数据未变更」，造成静默数据丢失。
        if (200..<300).contains(http.statusCode),
           let newETag = http.value(forHTTPHeaderField: "ETag"),
           !newETag.isEmpty {
            etagCache[cacheKey] = (token: CredentialStore.getToken() ?? "", etag: newETag)
        }

        if http.statusCode >= 400 {
            let errEnvelope = try? Self.makeDecoder().decode(APIEnvelope<EmptyPayload>.self, from: data)
            throw APIError.serverError(
                code: errEnvelope?.code ?? http.statusCode,
                message: errEnvelope?.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }

        // 解码是同步的，放到独立任务中执行，避免阻塞 actor 串行化其他请求
        do {
            let envelope: APIEnvelope<T> = try await Task.detached(priority: .userInitiated) {
                try Self.makeDecoder().decode(APIEnvelope<T>.self, from: data)
            }.value
            if envelope.code >= 400 {
                throw APIError.serverError(code: envelope.code, message: envelope.message)
            }
            guard let payload = envelope.data else {
                throw APIError.serverError(code: envelope.code, message: envelope.message)
            }
            return payload
        } catch let apiErr as APIError {
            throw apiErr
        } catch {
            throw APIError.decodingFailure(error.localizedDescription)
        }
    }

    private struct EmptyPayload: Codable, Sendable {}
    public struct DeleteResponse: Codable, Sendable {
        public var deleted: Bool?
        public var purged: Bool?
    }

    // MARK: - 1. 系统探针与鉴权配对 (Health, System & Device Pairing)

    public func checkHealth() async throws -> HealthCheckResponse {
        let (request, _) = try buildRequest(path: "/api/health")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await dataWithRetry(for: request, attempts: 2)
        } catch {
            throw APIError.networkFailure(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkFailure("健康探针响应无效")
        }
        // 保留真实状态码，便于排障（原先一律吞成「健康探针状态异常」）
        guard http.statusCode == 200 else {
            throw APIError.serverError(
                code: http.statusCode,
                message: "健康探针状态异常 (HTTP \(http.statusCode))"
            )
        }
        return try Self.makeDecoder().decode(HealthCheckResponse.self, from: data)
    }

    public func fetchSystemStatus() async throws -> SystemStatus {
        try await performEnvelopeRequest(path: "/api/v1/system/status")
    }

    /// 配对工单（链接/二维码）握手确认配对 (POST /api/v1/auth/pair/confirm)
    public func confirmPairing(
        ticket: String,
        deviceName: String,
        deviceModel: String = "Mac"
    ) async throws -> ConfirmPairingResponse {
        let payload = ConfirmPairingRequest(
            ticket: ticket,
            deviceName: deviceName,
            platform: "macos",
            deviceModel: deviceModel
        )
        let resp: ConfirmPairingResponse = try await performEnvelopeRequest(
            path: "/api/v1/auth/pair/confirm",
            method: "POST",
            body: payload
        )
        guard CredentialStore.saveToken(resp.deviceToken),
              CredentialStore.saveDeviceIdentity(deviceId: resp.deviceId, deviceName: resp.deviceName) else {
            throw APIError.serverError(
                code: 0,
                message: "无法写入本机凭据档案（磁盘权限或空间异常），配对未生效，请检查后重试"
            )
        }
        if let hub = resp.hubUrl, !hub.isEmpty {
            setBaseURL(hub)
        }
        return resp
    }

    /// 输入管理员密钥直接授权并签发设备令牌 (POST /api/v1/auth/verify)
    public func verifyMasterPasscode(
        passcode: String,
        deviceName: String,
        platform: String = "macos",
        deviceModel: String = "Mac"
    ) async throws -> VerifyPasscodeResponse {
        let payload = VerifyPasscodeRequest(
            passcode: passcode,
            deviceName: deviceName,
            platform: platform,
            deviceModel: deviceModel
        )
        let resp: VerifyPasscodeResponse = try await performEnvelopeRequest(
            path: "/api/v1/auth/verify",
            method: "POST",
            body: payload
        )
        guard CredentialStore.saveToken(resp.token),
              CredentialStore.saveDeviceIdentity(deviceId: resp.deviceId, deviceName: resp.deviceName) else {
            throw APIError.serverError(
                code: 0,
                message: "无法写入本机凭据档案（磁盘权限或空间异常），授权未生效，请检查后重试"
            )
        }
        return resp
    }

    /// 签发新设备配对工单 (生成包含中枢地址与设备工单的配对深链)
    public func initPairing(deviceHint: String = "macOS 工作台发起配对") async throws -> PairTicketResponse {
        let req = PairInitRequest(hubUrl: baseURLString, deviceHint: deviceHint)
        return try await performEnvelopeRequest(
            path: "/api/v1/auth/pair/init",
            method: "POST",
            body: req
        )
    }

    /// 切换配对节点时动态重新渲染纸墨二维码 (GET /api/v1/auth/pair/qr)
    public func fetchPairQRCode(hubURL: String, ticket: String) async throws -> PairQRResponse {
        let query = [
            URLQueryItem(name: "hub", value: hubURL),
            URLQueryItem(name: "ticket", value: ticket)
        ]
        return try await performEnvelopeRequest(path: "/api/v1/auth/pair/qr", queryItems: query)
    }

    /// 获取已信任设备列表 (GET /api/v1/auth/devices)
    public func fetchTrustedDevices() async throws -> [TrustedDevice] {
        try await performEnvelopeRequest(path: "/api/v1/auth/devices")
    }

    /// 吊销受信任设备 (DELETE /api/v1/auth/devices/:id)
    public func revokeDevice(id: String) async throws {
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/auth/devices/\(escapePathComponent(id))",
            method: "DELETE"
        )
    }

    /// 修改已授信设备的备注名称及平台属性 (PUT /api/v1/auth/devices/:id)
    @discardableResult
    public func updateDeviceName(
        id: String,
        name: String? = nil,
        platform: String? = nil,
        deviceModel: String? = nil
    ) async throws -> TrustedDevice {
        struct Payload: Codable, Sendable {
            let name: String?
            let platform: String?
            let device_model: String?
        }
        return try await performEnvelopeRequest(
            path: "/api/v1/auth/devices/\(escapePathComponent(id))",
            method: "PUT",
            body: Payload(name: name, platform: platform, device_model: deviceModel)
        )
    }

    // MARK: - 2. 站点配置、主理人档案与统计 (Config, Profile & Stats)

    public func fetchSiteConfig() async throws -> SiteConfig {
        try await performEnvelopeRequest(path: "/api/v1/config")
    }

    public func fetchCuratorProfile() async throws -> CuratorProfile {
        try await performEnvelopeRequest(path: "/api/v1/profile")
    }

    public func updateCuratorProfile(_ req: UpdateProfileRequest) async throws -> CuratorProfile {
        try await performEnvelopeRequest(path: "/api/v1/profile", method: "PUT", body: req)
    }

    public func fetchGlobalStats() async throws -> GlobalStats {
        try await performEnvelopeRequest(path: "/api/v1/stats")
    }

    /// 分类字典响应有两种历史形态（`{items:[...]}` 与裸数组）。
    /// 首次探测后记住形态，之后只发一个请求；此处不再用 `try?` 把网络错误吞成空数组。
    private enum CategoriesResponseShape {
        case wrapped
        case plainArray
    }
    private var categoriesShape: CategoriesResponseShape?
    /// 形态缓存的时间戳：服务端切换响应形态后，客户端不应永久沿用旧形态
    private var categoriesShapeProbedAt: Date = .distantPast
    /// 形态缓存有效期（10 分钟）
    private static let categoriesShapeTTL: TimeInterval = 600

    public func fetchCategories(scope: String? = nil) async throws -> [CategoryOption] {
        var items: [URLQueryItem] = []
        if let scope, !scope.isEmpty {
            items.append(URLQueryItem(name: "scope", value: scope))
        }

        // 形态缓存过期后重新探测：服务端可能已切换响应形态，
        // 原实现永久沿用首次探测结果，会一直用错误的形态解析分类。
        if let shape = categoriesShape,
           Date().timeIntervalSince(categoriesShapeProbedAt) < Self.categoriesShapeTTL {
            switch shape {
            case .wrapped:
                do {
                    let response: CategoryResetResponse = try await performEnvelopeRequest(
                        path: "/api/v1/categories",
                        queryItems: items
                    )
                    return response.items ?? []
                } catch let error as APIError {
                    // 形态可能已失效（服务端切换了响应结构）：清除缓存并重新探测一次
                    guard case .decodingFailure = error else { throw error }
                    categoriesShape = nil
                }
            case .plainArray:
                do {
                    return try await performEnvelopeRequest(path: "/api/v1/categories", queryItems: items)
                } catch let error as APIError {
                    guard case .decodingFailure = error else { throw error }
                    categoriesShape = nil
                }
            }
        }

        do {
            let response: CategoryResetResponse = try await performEnvelopeRequest(
                path: "/api/v1/categories",
                queryItems: items
            )
            categoriesShape = .wrapped
            categoriesShapeProbedAt = Date()
            return response.items ?? []
        } catch let error as APIError {
            // 只有"解码形态不匹配"才值得换一种再试；网络/鉴权错误直接上抛
            if case .decodingFailure = error {
                let plain: [CategoryOption] = try await performEnvelopeRequest(
                    path: "/api/v1/categories",
                    queryItems: items
                )
                categoriesShape = .plainArray
                categoriesShapeProbedAt = Date()
                return plain
            }
            throw error
        }
    }

    public func addCategoryOption(scope: String, name: String) async throws -> CategoryOption {
        struct Payload: Codable, Sendable {
            let scope: String
            let name: String
        }
        return try await performEnvelopeRequest(
            path: "/api/v1/categories",
            method: "POST",
            body: Payload(scope: scope, name: name)
        )
    }

    public func deleteCategoryOption(id: Int) async throws {
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/categories/\(id)",
            method: "DELETE"
        )
    }

    /// 获取那年今日历史归档 (GET /api/v1/entries/on-this-day)
    public func fetchOnThisDayEntries() async throws -> OnThisDayResponse {
        try await performEnvelopeRequest(path: "/api/v1/entries/on-this-day")
    }

    /// 全库跨模块搜索 (GET /api/v1/search?q=...)
    public func searchGlobalArchive(query: String, limit: Int = 20) async throws -> GlobalSearchResponse {
        let items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await performEnvelopeRequest(path: "/api/v1/search", queryItems: items)
    }

    // MARK: - 3. 生活档案 (Life Entries CRUD & Delta Sync)

    public func fetchEntries(
        page: Int = 1,
        pageSize: Int = 50,
        category: String? = nil,
        year: Int? = nil,
        since: String? = nil,
        useETag: Bool = false
    ) async throws -> EntriesListResponse {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ]
        if let category, !category.isEmpty, category != "all" {
            query.append(URLQueryItem(name: "category", value: category))
        }
        if let year {
            query.append(URLQueryItem(name: "year", value: String(year)))
        }
        if let since, !since.isEmpty {
            query.append(URLQueryItem(name: "since", value: since))
        }
        return try await performEnvelopeRequest(
            path: "/api/v1/entries",
            queryItems: query,
            useETag: useETag
        )
    }

    public func createEntry(_ req: CreateEntryRequest) async throws -> LifeEntry {
        try await performEnvelopeRequest(path: "/api/v1/entries", method: "POST", body: req)
    }

    public func updateEntry(id: Int, _ req: UpdateEntryRequest) async throws -> LifeEntry {
        try await performEnvelopeRequest(path: "/api/v1/entries/\(id)", method: "PUT", body: req)
    }

    public func deleteEntry(id: Int, purge: Bool = false) async throws {
        var query: [URLQueryItem] = []
        if purge {
            query.append(URLQueryItem(name: "purge", value: "true"))
        }
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/entries/\(id)",
            method: "DELETE",
            queryItems: query
        )
    }

    // MARK: - 4. 独立记账与资产管理中枢 (Transactions & Assets Hub)

    public func fetchTransactions(
        year: Int? = nil,
        month: Int? = nil,
        since: String? = nil,
        limit: Int = 200,
        offset: Int? = nil,
        useETag: Bool = false
    ) async throws -> [Transaction] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let offset, offset > 0 {
            query.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        if let year {
            query.append(URLQueryItem(name: "year", value: String(year)))
        }
        if let month {
            query.append(URLQueryItem(name: "month", value: String(month)))
        }
        if let since, !since.isEmpty {
            query.append(URLQueryItem(name: "since", value: since))
        }
        return try await performEnvelopeRequest(
            path: "/api/v1/transactions",
            queryItems: query,
            useETag: useETag
        )
    }

    public func fetchTransactionSummary(year: Int? = nil, month: Int? = nil) async throws -> TransactionSummary {
        var query: [URLQueryItem] = []
        if let year {
            query.append(URLQueryItem(name: "year", value: String(year)))
        }
        if let month {
            query.append(URLQueryItem(name: "month", value: String(month)))
        }
        return try await performEnvelopeRequest(
            path: "/api/v1/transactions/summary",
            queryItems: query
        )
    }

    public func createTransaction(_ req: CreateTransactionRequest) async throws -> Transaction {
        try await performEnvelopeRequest(path: "/api/v1/transactions", method: "POST", body: req)
    }

    public func updateTransaction(id: Int, _ req: CreateTransactionRequest) async throws -> Transaction {
        try await performEnvelopeRequest(path: "/api/v1/transactions/\(id)", method: "PUT", body: req)
    }

    public func deleteTransaction(id: Int, purge: Bool = false) async throws {
        var query: [URLQueryItem] = []
        if purge {
            query.append(URLQueryItem(name: "purge", value: "true"))
        }
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/transactions/\(id)",
            method: "DELETE",
            queryItems: query
        )
    }

    public func fetchAssetsOverview() async throws -> AssetsOverview {
        try await performEnvelopeRequest(path: "/api/v1/assets/overview")
    }

    public func updateInitialLiquidBalance(cents: Int64) async throws {
        struct Payload: Codable {
            let initial_liquid_balance: Int64
        }
        let _: EmptyPayload = try await performEnvelopeRequest(
            path: "/api/v1/assets/liquid-balance",
            method: "PUT",
            body: Payload(initial_liquid_balance: cents)
        )
    }

    public func addGearAsset(_ req: AddGearAssetRequest) async throws -> GearItem {
        try await performEnvelopeRequest(path: "/api/v1/assets/gear", method: "POST", body: req)
    }

    public func sellGearAsset(id: String, _ req: SellGearRequest) async throws -> GearItem {
        try await performEnvelopeRequest(path: "/api/v1/assets/gear/\(escapePathComponent(id))/sell", method: "POST", body: req)
    }

    /// 恢复一件被删除的随身设备（⌘Z 撤销用）
    ///
    /// 关键：设备本体存在**主理人档案的 JSON 列**里，删除是「从数组里移除」——
    /// 没有 deleted_at 可标记，所以恢复必须把**原始设备数据**带回去，
    /// 由服务端按原 id 插回（并连带恢复伴生散页）。
    public func restoreGearAsset(_ gear: GearItem, index: Int) async throws {
        let req = RestoreGearAssetRequest(
            id: gear.id,
            name: gear.name,
            spec: gear.spec,
            category: gear.category,
            status: gear.status,
            priceCents: gear.priceCents,
            purchaseDate: gear.purchaseDate,
            soldPriceCents: gear.soldPriceCents,
            soldDate: gear.soldDate,
            note: gear.note,
            index: index
        )
        let _: RestoreGearAssetResponse = try await performEnvelopeRequest(
            path: "/api/v1/assets/gear/restore",
            method: "POST",
            body: req
        )
    }

    public func deleteGearAsset(id: String) async throws {
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/assets/gear/\(escapePathComponent(id))",
            method: "DELETE"
        )
    }

    public func fetchCreditChannels() async throws -> [CreditChannel] {
        try await performEnvelopeRequest(path: "/api/v1/credit-channels")
    }

    public func createCreditChannel(_ req: CreateCreditChannelRequest) async throws -> CreditChannel {
        try await performEnvelopeRequest(path: "/api/v1/credit-channels", method: "POST", body: req)
    }

    public func updateCreditChannel(id: Int, _ req: CreateCreditChannelRequest) async throws -> CreditChannel {
        try await performEnvelopeRequest(path: "/api/v1/credit-channels/\(id)", method: "PUT", body: req)
    }

    public func deleteCreditChannel(id: Int) async throws {
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/credit-channels/\(id)",
            method: "DELETE"
        )
    }

    /// 首次装帧初始化 (POST /api/v1/system/bootstrap)
    public func bootstrapSystem(_ req: BootstrapRequest) async throws -> PairTicketResponse {
        try await performEnvelopeRequest(path: "/api/v1/system/bootstrap", method: "POST", body: req)
    }

    // MARK: - 5. 造物、心愿单与旅游足迹 (Projects, Wishes & Footprints)

    public func fetchProjects() async throws -> [Project] {
        try await performEnvelopeRequest(path: "/api/v1/projects")
    }

    public func createProject(_ req: CreateProjectRequest) async throws -> Project {
        try await performEnvelopeRequest(path: "/api/v1/projects", method: "POST", body: req)
    }

    public func updateProject(id: Int, _ req: CreateProjectRequest) async throws -> Project {
        try await performEnvelopeRequest(path: "/api/v1/projects/\(id)", method: "PUT", body: req)
    }

    public func deleteProject(id: Int) async throws {
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/projects/\(id)",
            method: "DELETE"
        )
    }

    public func fetchWishes(
        page: Int = 1,
        pageSize: Int = 100,
        kind: String? = nil,
        status: String? = nil
    ) async throws -> WishesListResponse {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ]
        if let kind, !kind.isEmpty, kind != "all" {
            query.append(URLQueryItem(name: "kind", value: kind))
        }
        if let status, !status.isEmpty, status != "all" {
            query.append(URLQueryItem(name: "status", value: status))
        }
        return try await performEnvelopeRequest(path: "/api/v1/wishes", queryItems: query)
    }

    public func createWish(_ req: CreateWishRequest) async throws -> Wish {
        try await performEnvelopeRequest(path: "/api/v1/wishes", method: "POST", body: req)
    }

    public func updateWish(id: Int, _ req: CreateWishRequest) async throws -> Wish {
        try await performEnvelopeRequest(path: "/api/v1/wishes/\(id)", method: "PUT", body: req)
    }

    public func resolveWish(id: Int, _ req: ResolveWishRequest) async throws -> Wish {
        try await performEnvelopeRequest(path: "/api/v1/wishes/\(id)/resolve", method: "POST", body: req)
    }

    public func deleteWish(id: Int) async throws {
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/wishes/\(id)",
            method: "DELETE"
        )
    }

    public func fetchFootprints(year: Int? = nil) async throws -> [Footprint] {
        var query: [URLQueryItem] = []
        if let year {
            query.append(URLQueryItem(name: "year", value: String(year)))
        }
        return try await performEnvelopeRequest(path: "/api/v1/footprints", queryItems: query)
    }

    public func createFootprint(_ req: CreateFootprintRequest) async throws -> Footprint {
        try await performEnvelopeRequest(path: "/api/v1/footprints", method: "POST", body: req)
    }

    public func updateFootprint(id: Int, _ req: CreateFootprintRequest) async throws -> Footprint {
        try await performEnvelopeRequest(path: "/api/v1/footprints/\(id)", method: "PUT", body: req)
    }

    public func deleteFootprint(id: Int) async throws {
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/footprints/\(id)",
            method: "DELETE"
        )
    }

    /// 获取单座城市回忆抽屉四重聚合数据 (GET /api/v1/footprints/cities/:city_code/drawer)
    public func fetchCityMemoryDrawer(cityCode: String) async throws -> CityMemoryDrawerResponse {
        try await performEnvelopeRequest(path: "/api/v1/footprints/cities/\(escapePathComponent(cityCode))/drawer")
    }

    /// 获取省级回忆抽屉聚合数据 (GET /api/v1/footprints/provinces/:adcode/drawer)
    public func fetchProvinceMemoryDrawer(adcode: String) async throws -> ProvinceMemoryDrawerResponse {
        try await performEnvelopeRequest(path: "/api/v1/footprints/provinces/\(escapePathComponent(adcode))/drawer")
    }

    /// 获取年度生活年鉴五幕聚合数据 (GET /api/v1/almanac/summary?year=...)
    public func fetchAnnualAlmanac(year: Int? = nil) async throws -> AnnualAlmanacResponse {
        var query: [URLQueryItem] = []
        if let year {
            query.append(URLQueryItem(name: "year", value: String(year)))
        }
        return try await performEnvelopeRequest(path: "/api/v1/almanac/summary", queryItems: query)
    }

    // MARK: - 6. 媒体预签名与统一上传 (R2 Presign & Multipart Fallback)

    public func presignUpload(_ req: PresignUploadRequest) async throws -> PresignUploadResponse {
        try await performEnvelopeRequest(path: "/api/v1/uploads/presign", method: "POST", body: req)
    }

    public func completeUpload(_ req: CompleteUploadRequest) async throws -> Attachment {
        try await performEnvelopeRequest(path: "/api/v1/uploads/complete", method: "POST", body: req)
    }

    // MARK: - 媒体签名地址换签 (Media URL Re-Signing)

    /// 批量换取新鲜的媒体签名地址
    ///
    /// 关键：快照持久化了 `attachment.url` / `thumbnailUrl`，
    /// 而它们是**会过期**的签名地址（本机媒体签名 30 分钟、R2 预签名同理）。
    /// 快照离线读出来时这些地址可能早已失效 ⇒ 相纸显示「载入失败」
    /// （磁盘缓存热时能兜住，冷缓存兜不住）。
    ///
    /// 离线时的兜底由本地磁盘缓存承担（缓存键剥掉预签名参数，跨签名稳定），
    /// 这里负责的是「联网时把地址换成新鲜的」。
    ///
    /// - Parameter objectKeys: 需要换签的 object key 列表
    /// - Returns: object key → (原图地址, 缩略图地址)
    public func refreshMediaURLs(
        objectKeys: [String],
        expiresIn: Int = 1800
    ) async throws -> [String: RefreshedMediaURLs] {
        guard !objectKeys.isEmpty else { return [:] }
        let req = BatchSignRequest(keys: objectKeys, expiresIn: expiresIn)
        let resp: BatchSignResponse = try await performEnvelopeRequest(
            path: "/api/v1/files/sign-batch",
            method: "POST",
            body: req
        )
        var out: [String: RefreshedMediaURLs] = [:]
        for item in resp.items {
            guard !item.objectKey.isEmpty else { continue }
            out[item.objectKey] = RefreshedMediaURLs(
                url: item.url,
                thumbnailUrl: item.thumbnailUrl
            )
        }
        return out
    }

    /// 本地未配置 R2 时的统一 multipart/form-data 上传通道 (POST /api/v1/files/upload)
    public func uploadUnifiedMultipart(
        fileData: Data,
        filename: String,
        mimeType: String,
        folder: String = "entries"
    ) async throws -> Attachment {
        let boundary = "Boundary-\(UUID().uuidString)"

        // multipart 请求体写入临时文件后用 upload(for:fromFile:) 发送，
        // 避免把整张图片在内存中再复制一份（峰值内存从 2× 降到 1×）。
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("looseleaf-upload-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        // 关键：必须先显式创建文件再打开写入句柄。
        // `FileHandle(forWritingTo:)` 在文件不存在时**会抛错**（不会自动创建），
        // 一旦漏掉这一步，multipart 上传会 100% 失败 —— 而 R2 未配置时的回退路径
        // 正是走这里，于是表现为「本地中枢下图片根本传不上去」。
        if !FileManager.default.createFile(atPath: bodyURL.path, contents: nil) {
            throw APIError.networkFailure("无法创建上传临时文件")
        }
        guard let handle = try? FileHandle(forWritingTo: bodyURL) else {
            throw APIError.networkFailure("无法打开上传临时文件")
        }
        defer { try? handle.close() }

        func appendString(_ str: String) {
            if let d = str.data(using: .utf8) {
                handle.write(d)
            }
        }

        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"folder\"\r\n\r\n")
        appendString("\(folder)\r\n")

        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        handle.write(fileData)
        appendString("\r\n--\(boundary)--\r\n")
        try? handle.synchronize()

        let (request, _) = try buildRequest(
            path: "/api/v1/files/upload",
            method: "POST",
            bodyData: nil,
            contentType: "multipart/form-data; boundary=\(boundary)",
            timeout: 180
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.upload(for: request, fromFile: bodyURL)
        } catch {
            throw APIError.networkFailure(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkFailure("上传响应无效")
        }
        if http.statusCode == 401 {
            NotificationCenter.default.post(name: .looseLeafUnauthorized, object: nil)
            throw APIError.unauthorized("上传需要设备授权凭据")
        }
        // 关键：先判状态码再解码。否则服务端返回 502 HTML 错误页会抛裸 DecodingError，
        // 上层无法识别为 APIError，会误判为「应回退到本地存储」并把整张图重传一次。
        guard http.statusCode == 200 else {
            let errEnvelope = try? Self.makeDecoder().decode(APIEnvelope<EmptyPayload>.self, from: data)
            throw APIError.serverError(
                code: errEnvelope?.code ?? http.statusCode,
                message: errEnvelope?.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        let envelope: APIEnvelope<UnifiedUploadResponse>
        do {
            envelope = try await Task.detached(priority: .userInitiated) {
                // JSONDecoder 不是线程安全的：不能复用 static decoder 跨任务并发解码。
                // 这里每次上传完成都是独立任务，创建局部 decoder 的成本远低于竞态风险。
                let decoder = JSONDecoder()
                return try decoder.decode(APIEnvelope<UnifiedUploadResponse>.self, from: data)
            }.value
        } catch {
            throw APIError.decodingFailure(error.localizedDescription)
        }
        guard let res = envelope.data else {
            throw APIError.serverError(code: envelope.code, message: envelope.message)
        }
        return Attachment(
            id: res.attachmentId,
            objectKey: res.objectKey,
            originalFilename: res.filename,
            mimeType: res.mimeType,
            size: res.size,
            width: res.width,
            height: res.height,
            url: res.url,
            // 刚上传完的附件也要能立刻用缩略图展示，
            // 否则在下次同步之前它仍会走原图（1.5MB / 4.4 秒）
            thumbnailUrl: res.thumbnailUrl
        )
    }

    // MARK: - 9. 数据中枢全量快照备份与回滚 (System Backups)

    public func fetchServerBackups() async throws -> [ServerBackupItem] {
        try await performEnvelopeRequest(path: "/api/v1/system/backup/list")
    }

    public func createServerBackupNow() async throws -> ServerBackupItem {
        try await performEnvelopeRequest(path: "/api/v1/system/backup/now", method: "POST")
    }

    public func deleteServerBackup(filename: String) async throws -> [ServerBackupItem] {
        try await performEnvelopeRequest(path: "/api/v1/system/backup/\(escapePathComponent(filename))", method: "DELETE")
    }

    public func restoreServerBackup(filename: String) async throws {
        struct RestoreReq: Encodable {
            let filename: String
        }
        let _: RestoreBackupResponse = try await performEnvelopeRequest(
            path: "/api/v1/system/backup/restore",
            method: "POST",
            body: RestoreReq(filename: filename)
        )
    }

    public func downloadServerBackup(filename: String) async throws -> (Data, String) {
        let (request, _) = try buildRequest(
            path: "/api/v1/system/backup/download/\(escapePathComponent(filename))",
            method: "GET",
            timeout: 180
        )
        // 先用 download(for: 拿到临时文件（流式落盘，避免整包驻留内存），再读入 Data 交给既有调用方
        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            throw APIError.networkFailure(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkFailure("下载响应无效")
        }
        if http.statusCode == 401 {
            NotificationCenter.default.post(name: .looseLeafUnauthorized, object: nil)
            throw APIError.unauthorized("下载备份需要设备授权凭据")
        }
        guard http.statusCode == 200 else {
            throw APIError.serverError(code: http.statusCode, message: "下载备份失败 (HTTP \(http.statusCode))")
        }
        let data = try Data(contentsOf: tempURL, options: .mappedIfSafe)
        return (data, filename)
    }

    // MARK: - 10. 中枢云端对象存储与灾备管理 (Storage Management)

    public func fetchStorageStatus() async throws -> StorageStatus {
        try await performEnvelopeRequest(path: "/api/v1/storage/status")
    }

    public func testStorageConfig(_ payload: StorageConfigPayload) async throws -> StorageTestResponse {
        try await performEnvelopeRequest(
            path: "/api/v1/storage/test",
            method: "POST",
            body: payload
        )
    }

    public func updateStorageConfig(_ payload: StorageConfigPayload) async throws -> StorageStatus {
        try await performEnvelopeRequest(
            path: "/api/v1/storage/config",
            method: "PUT",
            body: payload
        )
    }

    public func resetStorageConfig() async throws -> StorageStatus {
        try await performEnvelopeRequest(
            path: "/api/v1/storage/config",
            method: "DELETE"
        )
    }

    public func migrateStorageMedia() async throws -> StorageMigrateResponse {
        try await performEnvelopeRequest(
            path: "/api/v1/storage/migrate",
            method: "POST"
        )
    }
}

