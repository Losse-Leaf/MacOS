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
        }
    }
}

/// RESTful API v1 异步网络客户端
/// 对接 Go 后端数据中枢，支持 ETag / 304 缓存协商与受信任设备子钥匙鉴权
public actor APIClient {
    public static let shared = APIClient()
    public static let hubURLDefaultsKey = "looseleaf_hub_base_url"

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "api")

    private let session: URLSession
    private var etagCache: [String: String] = [:]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Hub 地址与媒体路径解析

    public nonisolated var baseURLString: String {
        let saved = UserDefaults.standard.string(forKey: Self.hubURLDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if saved.isEmpty {
            return "http://localhost:8088"
        }
        return saved.hasSuffix("/") ? String(saved.dropLast()) : saved
    }

    public nonisolated func setBaseURL(_ urlString: String) {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        UserDefaults.standard.set(cleaned, forKey: Self.hubURLDefaultsKey)
    }

    /// 将后端返回的相对媒体路径 (如 /media/...) 补全为可访问的完整 URL
    public nonisolated func resolveMediaURL(_ rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let prefix = baseURLString
        let path = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: "\(prefix)\(path)")
    }

    // MARK: - 通用请求构建与执行

    private func buildRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        bodyData: Data? = nil,
        contentType: String = "application/json",
        useETag: Bool = false
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
        request.timeoutInterval = 30

        if let bodyData {
            request.httpBody = bodyData
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        if let token = CredentialStore.getToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Device-Token")
        }

        if useETag, method == "GET", let cachedETag = etagCache[cacheKey] {
            request.setValue(cachedETag, forHTTPHeaderField: "If-None-Match")
        }

        return (request, cacheKey)
    }

    private func performEnvelopeRequest<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        useETag: Bool = false
    ) async throws -> T {
        let bodyData: Data?
        if let body {
            bodyData = try JSONEncoder().encode(body)
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
            (data, response) = try await session.data(for: request)
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
            let errEnvelope = try? JSONDecoder().decode(APIEnvelope<EmptyPayload>.self, from: data)
            Self.logger.warning("Received 401 unauthorized from \(path, privacy: .public)")
            NotificationCenter.default.post(name: .looseLeafUnauthorized, object: nil)
            throw APIError.unauthorized(errEnvelope?.message ?? "")
        }

        if let newETag = http.value(forHTTPHeaderField: "ETag"), !newETag.isEmpty {
            etagCache[cacheKey] = newETag
        }

        do {
            let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
            if http.statusCode >= 400 || envelope.code >= 400 {
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
        public var id: String?
        public var deleted: Bool?
        public var purged: Bool?
    }

    // MARK: - 1. 系统探针与鉴权配对 (Health, System & Device Pairing)

    public func checkHealth() async throws -> HealthCheckResponse {
        let (request, _) = try buildRequest(path: "/api/health")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.networkFailure("健康探针状态异常")
        }
        return try JSONDecoder().decode(HealthCheckResponse.self, from: data)
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
        CredentialStore.saveToken(resp.deviceToken)
        CredentialStore.saveDeviceIdentity(deviceId: resp.deviceId, deviceName: resp.deviceName)
        if let hub = resp.hubUrl, !hub.isEmpty {
            setBaseURL(hub)
        }
        return resp
    }

    /// 输入管理员密钥直接授权并签发设备令牌 (POST /api/v1/auth/verify)
    public func verifyMasterPasscode(passcode: String, deviceName: String) async throws -> VerifyPasscodeResponse {
        let payload = VerifyPasscodeRequest(passcode: passcode, deviceName: deviceName)
        let resp: VerifyPasscodeResponse = try await performEnvelopeRequest(
            path: "/api/v1/auth/verify",
            method: "POST",
            body: payload
        )
        CredentialStore.saveToken(resp.token)
        CredentialStore.saveDeviceIdentity(deviceId: resp.deviceId, deviceName: resp.deviceName)
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

    /// 获取已信任设备列表 (GET /api/v1/auth/devices)
    public func fetchTrustedDevices() async throws -> [TrustedDevice] {
        try await performEnvelopeRequest(path: "/api/v1/auth/devices")
    }

    /// 吊销受信任设备 (DELETE /api/v1/auth/devices/:id)
    public func revokeDevice(id: String) async throws {
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/auth/devices/\(id)",
            method: "DELETE"
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

    public func fetchCategories(scope: String? = nil) async throws -> [CategoryOption] {
        var items: [URLQueryItem] = []
        if let scope, !scope.isEmpty {
            items.append(URLQueryItem(name: "scope", value: scope))
        }
        return try await performEnvelopeRequest(path: "/api/v1/categories", queryItems: items)
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
        try await performEnvelopeRequest(path: "/api/v1/assets/gear/\(id)/sell", method: "POST", body: req)
    }

    public func deleteGearAsset(id: String) async throws {
        let _: DeleteResponse = try await performEnvelopeRequest(
            path: "/api/v1/assets/gear/\(id)",
            method: "DELETE"
        )
    }

    public func fetchCreditChannels() async throws -> [CreditChannel] {
        try await performEnvelopeRequest(path: "/api/v1/credit-channels")
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

    // MARK: - 6. 媒体预签名与统一上传 (R2 Presign & Multipart Fallback)

    public func presignUpload(_ req: PresignUploadRequest) async throws -> PresignUploadResponse {
        try await performEnvelopeRequest(path: "/api/v1/uploads/presign", method: "POST", body: req)
    }

    public func completeUpload(_ req: CompleteUploadRequest) async throws -> Attachment {
        try await performEnvelopeRequest(path: "/api/v1/uploads/complete", method: "POST", body: req)
    }

    /// 本地未配置 R2 时的统一 multipart/form-data 上传通道 (POST /api/v1/files/upload)
    public func uploadUnifiedMultipart(
        fileData: Data,
        filename: String,
        mimeType: String,
        folder: String = "entries"
    ) async throws -> Attachment {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func appendString(_ str: String) {
            if let d = str.data(using: .utf8) {
                body.append(d)
            }
        }

        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"folder\"\r\n\r\n")
        appendString("\(folder)\r\n")

        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        appendString("\r\n--\(boundary)--\r\n")

        let (request, _) = try buildRequest(
            path: "/api/v1/files/upload",
            method: "POST",
            bodyData: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkFailure("上传响应无效")
        }
        if http.statusCode == 401 {
            NotificationCenter.default.post(name: .looseLeafUnauthorized, object: nil)
            throw APIError.unauthorized("上传需要设备授权凭据")
        }
        let envelope = try JSONDecoder().decode(APIEnvelope<UnifiedUploadResponse>.self, from: data)
        guard http.statusCode == 200, let res = envelope.data else {
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
            url: res.url
        )
    }
}
