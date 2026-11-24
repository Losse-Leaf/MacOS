import XCTest
import Foundation
@testable import LooseLeaf

/// macOS 端**全功能用户走查** (End-to-End Feature Walkthrough)
///
/// 目的：像真实用户一样把每个功能都走一遍，既验证功能可用，也**测量每一步的耗时**，
/// 把「很卡」这种主观感受变成可定位的客观数据。
///
/// 与 XCUITest 的分工：
/// - XCUITest 覆盖「点了会怎样」（需要开发证书，本机不可用）
/// - 本测试覆盖「每个功能链路通不通 + 慢在哪」（可在 CI 常驻）
///
/// 前置：本地中枢需在 `http://localhost:8088` 运行。
/// 若不可达，测试会显式跳过而不是静默通过。
@MainActor
final class ArchiveWalkthroughTests: XCTestCase {

    private var timings: [(String, TimeInterval)] = []
    private let localHub = "http://localhost:8088"
    /// 走查前的凭据档案快照（结束后还原）
    private var savedToken: String?
    private var savedDeviceId: String?
    private var savedDeviceName: String?

    /// 走查专用的凭据目录
    ///
    /// **关键：走查必须完全隔离在自己的目录里。**
    /// 早期版本直接往真实凭据档案写走查令牌，tearDown 时若「快照到的旧令牌」
    /// 为空就会调 `deleteToken()` —— 那等于**把用户真实配对的令牌删掉**，
    /// 用户重新打开 App 只能看到配对门禁。
    /// 现在整个走查在独立目录里进行，真实凭据档案连读都不会碰到。
    private var isolatedCredentialDirectory: URL?

    override func setUp() async throws {
        try await super.setUp()

        // 隔离：整个走查只在临时目录里读写凭据，绝不碰用户的真实凭据档案
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("looseleaf-walkthrough-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        CredentialStore.overrideDirectory = dir
        isolatedCredentialDirectory = dir

        APIClient.shared.setBaseURL(localHub)
        savedToken = CredentialStore.getToken()
        savedDeviceId = CredentialStore.getDeviceId()
        savedDeviceName = CredentialStore.getDeviceName()
        guard await hubIsReachable() else {
            throw XCTSkip("本地中枢未启动（\(localHub)），跳过全功能走查")
        }
        try await ensurePaired()
    }

    override func tearDown() async throws {
        printTimings()
        restoreCredentialStore()
        // 解除隔离并清掉临时目录
        CredentialStore.overrideDirectory = nil
        if let dir = isolatedCredentialDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        isolatedCredentialDirectory = nil
        try await super.tearDown()
    }

    // MARK: - 基础设施

    private func hubIsReachable() async -> Bool {
        var request = URLRequest(url: URL(string: "\(localHub)/api/health")!)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// 走查专用设备令牌。
    ///
    /// 说明：`/auth/pair/init` 本身需要管理员鉴权，因此**无法**用它自助签发工单。
    /// 走查改为使用一个预先植入本地中枢的专用设备令牌
    /// （`scripts/seed_walkthrough_device.py` 负责植入），行为与真实已配对设备一致。
    private static let walkthroughToken = "lldt_walkthrough_test_token_0001"

    private func ensurePaired() async throws {
        _ = CredentialStore.saveToken(Self.walkthroughToken)
        _ = CredentialStore.saveDeviceIdentity(deviceId: "dev_walkthrough_test", deviceName: "走查测试设备")
    }

    /// 走查期间会临时写入走查令牌，用完必须还原，
    /// 否则会污染同进程内其它测试对凭据档案的断言。
    private func restoreCredentialStore() {
        if let saved = savedToken {
            _ = CredentialStore.saveToken(saved)
        } else {
            CredentialStore.deleteToken()
        }
        if let savedDeviceId {
            _ = CredentialStore.saveDeviceIdentity(deviceId: savedDeviceId, deviceName: savedDeviceName ?? "走查测试设备")
        } else {
            CredentialStore.clearAllCredentials()
        }
    }

    /// 测量一步操作的耗时
    @discardableResult
    private func timed<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
        let start = Date()
        let result = try await body()
        let elapsed = Date().timeIntervalSince(start)
        timings.append((label, elapsed))
        print("⏱ [\(label)] \(String(format: "%.3f", elapsed))s")
        return result
    }

    private func printTimings() {
        guard !timings.isEmpty else { return }
        print("──────── 逐步耗时 ────────")
        for (label, elapsed) in timings {
            let flag = elapsed > 1.0 ? "  ⚠️ 慢" : ""
            print(String(format: "  %-40@ %.3fs%@", label as NSString, elapsed, flag as NSString))
        }
        print(String(format: "  合计 %.3fs", timings.reduce(0) { $0 + $1.1 }))
    }

    /// 翻遍所有页找出满足条件的散页
    ///
    /// 关键：伴生记录（如心愿圆梦）的 `occurred_at` 落在**历史日期**上，
    /// 当档案里已有大量更晚的记录时，它会排到很后面的页 —— 只查第 1 页会漏掉。
    private func findEntry(pages: Int = 20, pageSize: Int = 100, where predicate: (LifeEntry) -> Bool) async throws -> LifeEntry? {
        for page in 1...pages {
            let list = try await APIClient.shared.fetchEntries(page: page, pageSize: pageSize)
            if let hit = list.entries.first(where: predicate) { return hit }
            if list.entries.count < pageSize { break }
        }
        return nil
    }

    private func uniqueMarker(_ prefix: String) -> String {
        "\(prefix)-\(Int(Date().timeIntervalSince1970 * 1000))"
    }

    // MARK: - 1. 散页：创建 → 读取 → 编辑 → 删除

    func test01_EntryCreateReadUpdateDelete() async throws {
        let title = uniqueMarker("走查散页")

        // 创建
        let created = try await timed("创建散页") {
            try await APIClient.shared.createEntry(
                CreateEntryRequest(
                    type: "life",
                    title: title,
                    content: "端到端走查正文",
                    occurredAt: FormatUtils.beijingISOString(),
                    location: "杭州市"
                )
            )
        }
        XCTAssertGreaterThan(created.id, 0)

        // 读取（列表里应能查到）
        let list = try await timed("读取散页列表") {
            try await APIClient.shared.fetchEntries(page: 1, pageSize: 50)
        }
        XCTAssertTrue(list.entries.contains { $0.id == created.id }, "新建的散页未出现在列表里")

        // 编辑
        let updated = try await timed("编辑散页") {
            try await APIClient.shared.updateEntry(
                id: created.id,
                UpdateEntryRequest(
                    type: "life",
                    title: title + "-改",
                    content: "端到端走查正文（已改）",
                    occurredAt: FormatUtils.beijingISOString(),
                    location: "杭州市"
                )
            )
        }
        XCTAssertEqual(updated.title, title + "-改")

        // 删除
        try await timed("删除散页") {
            try await APIClient.shared.deleteEntry(id: created.id)
        }
        let afterDelete = try await APIClient.shared.fetchEntries(page: 1, pageSize: 50)
        XCTAssertFalse(afterDelete.entries.contains { $0.id == created.id }, "删除后散页仍在列表里")
    }

    // MARK: - 2. 心愿：创建 → 时间流出现 → 编辑 → 删除 → 时间流消失

    func test02_WishLifecycleAndTimelineSync() async throws {
        let title = uniqueMarker("走查心愿")

        let wish = try await timed("创建心愿") {
            try await APIClient.shared.createWish(
                CreateWishRequest(
                    title: title,
                    kind: "item",
                    note: "走查笔记",
                    spec: "规格",
                    budget: 12800,
                    plantedAt: FormatUtils.beijingISOString()
                )
            )
        }
        XCTAssertGreaterThan(wish.id, 0)

        // 关键契约：心愿在时间流里必须有一条伴生散页
        let companion = try await timed("心愿 → 时间流伴生散页") {
            try await findEntry { $0.wishId == wish.id }
        }
        XCTAssertNotNil(companion, "心愿在时间流里没有伴生散页")
        XCTAssertEqual(companion?.type, "wish")

        // 编辑心愿后，伴生散页的标题要同步
        _ = try await timed("编辑心愿") {
            try await APIClient.shared.updateWish(
                id: wish.id,
                CreateWishRequest(
                    title: title + "-改",
                    kind: "item",
                    note: "走查笔记",
                    spec: "规格",
                    budget: 12800
                )
            )
        }
        let syncedCompanion = try await findEntry { $0.wishId == wish.id }
        XCTAssertEqual(syncedCompanion?.title, "许下心愿 · \(title + "-改")", "编辑心愿后伴生散页标题未同步")
        let wishCompanions = try await findEntry { $0.wishId == wish.id }
        XCTAssertNotNil(wishCompanions, "编辑后伴生散页应仍然存在")

        // 删除心愿后，伴生散页要消失
        try await timed("删除心愿") {
            try await APIClient.shared.deleteWish(id: wish.id)
        }
        let orphanWish = try await findEntry { $0.wishId == wish.id }
        XCTAssertNil(orphanWish, "删除心愿后时间流仍留有伴生散页")
    }

    // MARK: - 5. 账目：创建 → 时间流合成条目 → 编辑 → 删除

    func test05_TransactionLifecycle() async throws {
        let title = uniqueMarker("走查账目")

        let tx = try await timed("创建账目") {
            try await APIClient.shared.createTransaction(
                CreateTransactionRequest(
                    amount: 4250,
                    type: "expense",
                    category: "餐饮",
                    title: title,
                    note: "走查备注",
                    paymentMethod: "微信支付",
                    occurredAt: FormatUtils.beijingISOString()
                )
            )
        }
        XCTAssertGreaterThan(tx.id, 0)

        let txs = try await timed("读取账目列表") {
            try await APIClient.shared.fetchTransactions(limit: 50, offset: 0)
        }
        XCTAssertTrue(txs.contains { $0.id == tx.id }, "新建的账目未出现在列表里")

        // 账目在时间流里是**客户端合成**的条目（服务端 entries 里并没有账目行），
        // 因此这里要验证的是合成逻辑本身，而不是服务端数据。
        let synthetic = tx.toLifeEntry()
        XCTAssertEqual(synthetic.associatedTransactionId, Int64(tx.id), "合成条目的账目 id 关联不正确")
        XCTAssertEqual(synthetic.type, "transaction")
        XCTAssertEqual(synthetic.title, tx.title)
        XCTAssertFalse(synthetic.content.isEmpty, "合成条目应带上账目摘要")

        try await timed("编辑账目") {
            try await APIClient.shared.updateTransaction(
                id: tx.id,
                CreateTransactionRequest(
                    amount: 4500,
                    type: "expense",
                    category: "餐饮",
                    title: title + "-改",
                    note: "走查备注",
                    paymentMethod: "微信支付",
                    occurredAt: FormatUtils.beijingISOString()
                )
            )
        }

        try await timed("删除账目") {
            try await APIClient.shared.deleteTransaction(id: tx.id)
        }
        let afterDelete = try await APIClient.shared.fetchTransactions(limit: 50, offset: 0)
        XCTAssertFalse(afterDelete.contains { $0.id == tx.id }, "删除后账目仍在列表里")
    }

    // MARK: - 7. 图片上传：预签名 → 直传 → 绑定

    func test07_ImageUploadFlow() async throws {
        // 造一张 1x1 的 PNG 作为上传源
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let fileName = uniqueMarker("走查图片") + ".png"

        let uploaded = try await timed("图片上传（预签名 + 直传 + 绑定）") {
            let photo = try ImageProcessor.processImageData(
                pngData,
                originalFilename: fileName
            )
            return try await R2DirectUploader.shared.uploadProcessedPhoto(photo)
        }
        XCTAssertGreaterThan(uploaded.id, 0, "图片上传未返回附件 id")
        XCTAssertFalse(uploaded.url.isEmpty, "图片附件缺少可访问 URL")

        // 把图片挂到一条散页上，验证附件绑定链路
        let entry = try await timed("散页绑定图片附件") {
            try await APIClient.shared.createEntry(
                CreateEntryRequest(
                    type: "life",
                    title: uniqueMarker("带图散页"),
                    content: "带附件的走查散页",
                    occurredAt: FormatUtils.beijingISOString(),
                    attachmentIds: [uploaded.id]
                )
            )
        }
        let withAttachment = try await APIClient.shared.fetchEntries(page: 1, pageSize: 100)
        let reloaded = withAttachment.entries.first { $0.id == entry.id }
        XCTAssertEqual(reloaded?.attachments.count, 1, "附件未正确绑定到散页")
    }

    // MARK: - 8. 读取路径：配置 / 档案 / 分类 / 统计 / 信用渠道

    func test08_AllReadEndpoints() async throws {
        try await timed("读取站点配置") { _ = try await APIClient.shared.fetchSiteConfig() }
        try await timed("读取主理人档案") { _ = try await APIClient.shared.fetchCuratorProfile() }
        try await timed("读取全局统计") { _ = try await APIClient.shared.fetchGlobalStats() }
        try await timed("读取分类字典") { _ = try await APIClient.shared.fetchCategories() }
        try await timed("读取心愿单") { _ = try await APIClient.shared.fetchWishes(page: 1, pageSize: 50) }
        try await timed("读取信用渠道") { _ = try await APIClient.shared.fetchCreditChannels() }
        try await timed("读取月度汇总") {
            let ym = FormatUtils.beijingCurrentYearMonth()
            _ = try await APIClient.shared.fetchTransactionSummary(year: ym.year, month: ym.month)
        }
    }

    // MARK: - 9. 搜索

    func test09_GlobalSearchReturnsResults() async throws {
        let marker = uniqueMarker("搜索目标")
        _ = try await APIClient.shared.createEntry(
            CreateEntryRequest(
                type: "life",
                title: marker,
                content: "用于走查搜索的独特关键词",
                occurredAt: FormatUtils.beijingISOString()
            )
        )
        let result = try await timed("全局检索") {
            try await APIClient.shared.searchGlobalArchive(query: marker, limit: 20)
        }
        XCTAssertTrue(
            result.entries.contains { $0.title.contains(marker) },
            "全局检索未召回刚创建的散页"
        )
    }
}

/// 纯本地离线状态机与字典走查（无需本地中枢在线，CI 与离线环境均常驻执行）
@MainActor
final class ArchiveLocalStateWalkthroughTests: XCTestCase {

    func test10_OptimisticWriteAppearsImmediately() throws {
        let appState = AppState.shared
        let title = "乐观散页-\(Int(Date().timeIntervalSince1970 * 1000))"

        let start = Date()
        let optimistic = SyncManager.shared.submitEntryOptimistically(
            CreateEntryRequest(
                type: "life",
                title: title,
                content: "乐观写入走查",
                occurredAt: FormatUtils.beijingISOString(),
                isPrivate: true
            )
        )
        defer {
            SyncManager.shared.removeOptimisticEntry(localTempId: optimistic.id)
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.1, "乐观写入本应是同步且瞬时的")
        XCTAssertTrue(
            appState.entries.contains { $0.id == optimistic.id },
            "乐观写入后条目未立即出现在本地时间流"
        )
        XCTAssertEqual(optimistic.syncStatus, "pending_create")
        XCTAssertTrue(optimistic.isPrivate, "乐观写入必须原样保留 isPrivate 私密标记")
    }
}
