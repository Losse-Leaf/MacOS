import Foundation
import SwiftUI
import Observation
import AppKit

/// 桌面端主题外观模式 (支持跟随系统、暖色棉纸、胶片暗房)
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case paper = "paper"
    case darkroom = "darkroom"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "跟随系统"
        case .paper: return "暖色棉纸"
        case .darkroom: return "暗房安全灯"
        }
    }

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .paper: return .light
        case .darkroom: return .dark
        }
    }
}

/// 桌面端主窗口侧栏导航模块
public enum WorkbenchSection: String, CaseIterable, Identifiable, Sendable {
    case stream = "stream"
    case darkroom = "darkroom"
    case ledger = "ledger"
    case creations = "creations"
    case dossier = "dossier"
    case settings = "settings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .stream: return "时间流与刻度"
        case .darkroom: return "拖拽暗房冲印"
        case .ledger: return "柴米油盐与资产"
        case .creations: return "造物、心愿与行迹"
        case .dossier: return "主理人手记与器物"
        case .settings: return "设备配对与偏好"
        }
    }

    public var icon: String {
        switch self {
        case .stream: return "book.pages"
        case .darkroom: return "camera.aperture"
        case .ledger: return "chart.bar.doc.horizontal"
        case .creations: return "sparkles.rectangle.stack"
        case .dossier: return "person.text.rectangle"
        case .settings: return "key.radiowaves.forward"
        }
    }
}

/// 全局响应式状态中心 (@Observable)
/// 遵循本地优先 (Local-First) 毫秒级上屏 + 后台异步增量同步架构
@Observable
@MainActor
public final class AppState {
    public static let shared = AppState()

    // MARK: - 核心业务数据 (100% 动态驱动，严禁假数据兜底)
    public var entries: [LifeEntry] = []
    public var transactions: [Transaction] = []
    public var transactionSummary: TransactionSummary = TransactionSummary()
    public var assetsOverview: AssetsOverview?
    public var profile: CuratorProfile = CuratorProfile()
    public var siteConfig: SiteConfig = SiteConfig()
    public var stats: GlobalStats = GlobalStats()
    public var projects: [Project] = []
    public var wishes: [Wish] = []
    public var footprints: [Footprint] = []
    public var trustedDevices: [TrustedDevice] = []
    public var creditChannels: [CreditChannel] = []
    public var outboxItems: [OutboxItem] = []

    // MARK: - 动态分类字典 (由 /api/v1/categories 下发驱动)
    public var expenseCategories: [String] = ["餐饮", "交通", "购物", "数码器材", "娱乐", "住房", "学习", "医疗", "其他"]
    public var paymentMethods: [String] = ["微信支付", "支付宝", "银行卡", "现金"]

    // MARK: - 导航与交互状态
    public var activeSection: WorkbenchSection = .stream
    public var selectedCategory: ArchiveCategory = .all
    public var searchQuery: String = ""
    public var selectedHashtag: String?
    public var highlightedEntry: LifeEntry?
    public var lightboxAttachment: Attachment?

    /// 键盘流（⌘↑ / ⌘↓）当前聚焦的时间流条目 ID
    public var keyboardFocusedEntryId: Int?

    /// 系统「服务」菜单摘录的待归档文本（QuickCaptureView 消费后清空）
    public var pendingCaptureText: String?

    // MARK: - 鉴权、网络与偏好设置状态
    public var isPaired: Bool = false
    public var hubURLString: String = APIClient.shared.baseURLString
    public var isLoading: Bool = false
    public var isOnline: Bool = true
    public var isFlushingOutbox: Bool = false
    public var statusBanner: String?
    public var errorBanner: String?

    public var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "looseleaf_appearance_mode")
        }
    }

    public var soundEnabled: Bool {
        didSet {
            AudioFeedback.shared.isSoundEnabled = soundEnabled
        }
    }

    public var hapticsEnabled: Bool {
        didSet {
            AudioFeedback.shared.isHapticsEnabled = hapticsEnabled
        }
    }

    public var globalHotkeyLabel: String { AppDelegate.hotKeyDisplayName }

    // MARK: - 派生数据记忆缓存（@ObservationIgnored：写入不触发视图更新）
    @ObservationIgnored private var dataRevision: Int = 0
    @ObservationIgnored private var filteredMemo: (key: String, value: [LifeEntry])?
    @ObservationIgnored private var hashtagMemo: (key: String, value: [(tag: String, count: Int)])?
    @ObservationIgnored private var entryCountsMemo: (key: String, value: [String: Int])?

    private init() {
        let savedAppearance = UserDefaults.standard.string(forKey: "looseleaf_appearance_mode") ?? AppearanceMode.system.rawValue
        self.appearanceMode = AppearanceMode(rawValue: savedAppearance) ?? .system
        self.soundEnabled = AudioFeedback.shared.isSoundEnabled
        self.hapticsEnabled = AudioFeedback.shared.isHapticsEnabled
        self.isPaired = (CredentialStore.getToken()?.isEmpty == false)

        // 1. 毫秒级载入本地持久化快照 (Local-First 0ms 白屏)
        self.isOnline = SyncManager.shared.isOnline
        self.isFlushingOutbox = SyncManager.shared.isFlushingOutbox
        applySnapshot(SyncManager.shared.currentSnapshot())

        SyncManager.shared.onNetworkStatusChanged = { [weak self] online in
            self?.isOnline = online
        }

        SyncManager.shared.onSnapshotUpdated = { [weak self] snap in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnline = SyncManager.shared.isOnline
                self.isFlushingOutbox = SyncManager.shared.isFlushingOutbox
                self.applySnapshot(snap)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .looseLeafUnauthorized,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                CredentialStore.deleteToken()
                self.isPaired = false
                self.errorBanner = "设备授权已过期或被吊销，请重新完成设备配对或验证主理人密钥"
            }
        }
    }

    private func applySnapshot(_ snap: LocalArchiveSnapshot) {
        self.entries = snap.entries
        self.transactions = snap.transactions
        self.transactionSummary = snap.transactionSummary
        self.profile = snap.profile
        self.siteConfig = snap.siteConfig
        self.stats = snap.stats
        self.outboxItems = snap.outbox
        dataRevision += 1
        // 系统搜索索引（Spotlight，异步派发不阻塞渲染）
        SpotlightIndexer.reindex(entries: snap.entries)
    }

    // MARK: - 过滤与检索计算属性

    /// 供主窗口展示的过滤后时间流列表（融合账目视角、分类过滤、#标签下钻与模糊搜索）
    /// 带记忆缓存：仅在数据版本或筛选条件变化时重算，渲染路径零重复过滤
    public var filteredStreamEntries: [LifeEntry] {
        let key = "\(dataRevision)|\(selectedCategory.rawValue)|\(searchQuery)|\(selectedHashtag ?? "")"
        if let memo = filteredMemo, memo.key == key {
            return memo.value
        }
        let computed = computeFilteredStreamEntries()
        filteredMemo = (key, computed)
        return computed
    }

    private func computeFilteredStreamEntries() -> [LifeEntry] {
        var source: [LifeEntry]
        if selectedCategory == .transaction {
            source = transactions.map { $0.toLifeEntry() }
        } else {
            source = entries.filter { $0.matches(category: selectedCategory) }
        }

        if let tag = selectedHashtag, !tag.isEmpty {
            source = source.filter { $0.hashtags.contains(tag) }
        }

        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            source = source.filter { entry in
                entry.title.lowercased().contains(q)
                || entry.content.lowercased().contains(q)
                || (entry.location?.lowercased().contains(q) ?? false)
                || (entry.cityName?.lowercased().contains(q) ?? false)
            }
        }
        return source
    }

    /// 聚合高频 #标签（带记忆缓存）
    public var allHashtags: [(tag: String, count: Int)] {
        let key = "\(dataRevision)"
        if let memo = hashtagMemo, memo.key == key {
            return memo.value
        }
        var map: [String: Int] = [:]
        for entry in entries {
            for tag in entry.hashtags {
                map[tag, default: 0] += 1
            }
        }
        let value = map
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (tag: $0.key, count: $0.value) }
        hashtagMemo = (key, value)
        return value
    }

    /// 按北京时间自然日聚合的记录密度（52 周热力图数据源，带记忆缓存）
    public var entryCountsByDate: [String: Int] {
        let key = "\(dataRevision)"
        if let memo = entryCountsMemo, memo.key == key {
            return memo.value
        }
        var counts: [String: Int] = [:]
        for entry in entries {
            counts[entry.parsedDate.dateKey, default: 0] += 1
        }
        entryCountsMemo = (key, counts)
        return counts
    }

    // MARK: - 远端全量与增量拉取

    public func refreshAll(forceFull: Bool = false) async {
        isLoading = true
        errorBanner = nil
        defer { isLoading = false }

        // 先尝试排空离线发件箱
        await SyncManager.shared.flushOutbox()

        // 并发拉取公开基础配置与档案
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadConfigAndProfile() }
            group.addTask { await self.loadEntries(forceFull: forceFull) }
            group.addTask { await self.loadCategories() }
            group.addTask { await self.loadProjectsWishesFootprints() }
            if self.isPaired {
                group.addTask { await self.loadTransactionsAndAssets(forceFull: forceFull) }
            }
        }
    }

    public func loadConfigAndProfile() async {
        let cfg = try? await APIClient.shared.fetchSiteConfig()
        let prof = try? await APIClient.shared.fetchCuratorProfile()
        let st = try? await APIClient.shared.fetchGlobalStats()
        SyncManager.shared.updateConfigAndProfile(siteConfig: cfg, profile: prof, stats: st)
    }

    public func loadCategories() async {
        guard let list = try? await APIClient.shared.fetchCategories() else { return }
        let exp = list.filter { $0.scope == "expense" }.map(\.name)
        if !exp.isEmpty {
            self.expenseCategories = exp
        }
        let pay = list.filter { $0.scope == "payment" }.map(\.name)
        if !pay.isEmpty {
            self.paymentMethods = pay
        }
    }

    public func loadEntries(forceFull: Bool = false) async {
        let snap = SyncManager.shared.currentSnapshot()
        // 关键保障：若本地 entries 尚为空，必须强制全量拉取，杜绝因残留 cursor 导致拉取空增量！
        let cursor = (forceFull || snap.entries.isEmpty) ? nil : snap.lastEntriesSyncCursor
        do {
            var currentPage = 1
            let pageSize = 100
            var allFetched: [LifeEntry] = []

            while true {
                let resp = try await APIClient.shared.fetchEntries(
                    page: currentPage,
                    pageSize: pageSize,
                    since: cursor,
                    useETag: !forceFull && cursor == nil && currentPage == 1
                )
                allFetched.append(contentsOf: resp.entries)
                if resp.entries.count < pageSize || allFetched.count >= resp.total {
                    break
                }
                currentPage += 1
            }

            SyncManager.shared.mergeEntries(allFetched, isDelta: cursor != nil)
        } catch APIError.notModified {
            // 304 Not Modified: 本地缓存已是最新
        } catch {
            if entries.isEmpty {
                self.errorBanner = error.localizedDescription
            }
        }
    }

    public func loadTransactionsAndAssets(forceFull: Bool = false) async {
        guard isPaired else { return }
        let snap = SyncManager.shared.currentSnapshot()
        let cursor = (forceFull || snap.transactions.isEmpty) ? nil : snap.lastTransactionsSyncCursor

        do {
            var allTxs: [Transaction] = []
            let batchLimit = 500
            var currentOffset = 0

            while true {
                let txs = try await APIClient.shared.fetchTransactions(
                    since: cursor,
                    limit: batchLimit,
                    offset: currentOffset,
                    useETag: !forceFull && cursor == nil && currentOffset == 0
                )
                allTxs.append(contentsOf: txs)
                if txs.count < batchLimit {
                    break
                }
                currentOffset += txs.count
            }

            SyncManager.shared.mergeTransactions(allTxs, isDelta: cursor != nil)
        } catch APIError.notModified {
            // 304 Not Modified
        } catch {
            // 保持本地缓存
        }

        let ym = FormatUtils.beijingCurrentYearMonth()
        if let summary = try? await APIClient.shared.fetchTransactionSummary(year: ym.year, month: ym.month) {
            SyncManager.shared.updateTransactionSummary(summary)
        }

        if let overview = try? await APIClient.shared.fetchAssetsOverview() {
            self.assetsOverview = overview
        }
        if let channels = try? await APIClient.shared.fetchCreditChannels() {
            self.creditChannels = channels
        }
    }

    public func loadProjectsWishesFootprints() async {
        if let projs = try? await APIClient.shared.fetchProjects() {
            self.projects = projs
        }
        var allWishes: [Wish] = []
        var wishPage = 1
        while true {
            guard let wishResp = try? await APIClient.shared.fetchWishes(page: wishPage, pageSize: 100) else { break }
            allWishes.append(contentsOf: wishResp.wishes)
            if wishResp.wishes.count < 100 || allWishes.count >= wishResp.total {
                break
            }
            wishPage += 1
        }
        if !allWishes.isEmpty {
            self.wishes = allWishes
        }
        if let fps = try? await APIClient.shared.fetchFootprints() {
            self.footprints = fps
        }
    }

    // MARK: - 键盘流导航（⌘↑ / ⌘↓ / ⌘↩）

    /// 在筛选后的时间流中上下移动键盘焦点（首次按下选中第一条）
    public func moveSelection(by delta: Int) {
        let list = filteredStreamEntries
        guard !list.isEmpty else { return }
        var index = keyboardFocusedEntryId.flatMap { id in
            list.firstIndex(where: { $0.id == id })
        } ?? 0
        index = min(max(index + delta, 0), list.count - 1)
        keyboardFocusedEntryId = list[index].id
        AudioFeedback.shared.playTink()
    }

    /// 打开当前键盘聚焦的散页详情
    public func openKeyboardFocusedEntry() {
        guard let id = keyboardFocusedEntryId,
              let entry = filteredStreamEntries.first(where: { $0.id == id }) else { return }
        highlightedEntry = entry
    }

    // MARK: - 极速闪念与快速记账提交 (Quick Capture & Quick Ledger)

    public func submitQuickCapture(
        title: String,
        content: String,
        type: EntryType = .life,
        location: String? = nil,
        attachmentIds: [Int] = [],
        featured: Bool = false,
        occurredAt: String? = nil
    ) async throws -> Bool {
        let finalLocation = (location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? location!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (profile.displayCity.isEmpty ? nil : profile.displayCity)

        let req = CreateEntryRequest(
            type: type.rawValue,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            occurredAt: occurredAt ?? FormatUtils.beijingISOString(),
            location: finalLocation,
            featured: featured,
            attachmentIds: attachmentIds
        )

        let (_, queuedOffline) = try await SyncManager.shared.submitEntry(req)
        AudioFeedback.shared.playShutter()
        if queuedOffline {
            showTemporaryBanner("已暂存至本地发件箱，网络恢复后自动同步")
        } else {
            showTemporaryBanner("已归入散页时间流")
            await loadConfigAndProfile()
        }
        return queuedOffline
    }

    public func submitQuickLedger(
        amountCents: Int64,
        type: String = "expense",
        category: String,
        title: String,
        note: String? = nil,
        paymentMethod: String? = nil
    ) async throws -> Bool {
        let req = CreateTransactionRequest(
            amount: amountCents,
            type: type,
            category: category,
            title: title,
            note: note,
            paymentMethod: paymentMethod ?? paymentMethods.first ?? "微信支付",
            occurredAt: FormatUtils.beijingISOString()
        )

        let (_, queuedOffline) = try await SyncManager.shared.submitTransaction(req)
        AudioFeedback.shared.playShutter()
        if queuedOffline {
            showTemporaryBanner("账单已暂存至本地发件箱，网络恢复后自动同步")
        } else {
            showTemporaryBanner("已记入账本：\(FormatUtils.formattedYuan(cents: amountCents, includeSymbol: true))")
            await loadTransactionsAndAssets(forceFull: true)
            await loadConfigAndProfile()
        }
        return queuedOffline
    }

    // MARK: - 设备配对与密钥授权 (Device Pairing & Credential Vault)

    /// 解析配对深链文本：`looseleaf://pair?hub=<中枢地址>&ticket=<配对工单>`
    /// hub 缺失时返回空串（调用方回退到当前 `hubURLString`）；ticket 缺失或非配对链接返回 nil。
    public nonisolated static func parsePairLink(_ raw: String) -> (hub: String, ticket: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme == "looseleaf",
              comps.host == "pair" else { return nil }
        let items = comps.queryItems ?? []
        let ticket = items.first(where: { $0.name == "ticket" })?.value ?? ""
        guard !ticket.isEmpty else { return nil }
        let hub = items.first(where: { $0.name == "hub" })?.value ?? ""
        return (hub, ticket)
    }

    public func pairWithTicket(_ ticket: String, hubURL: String) async throws {
        APIClient.shared.setBaseURL(hubURL)
        self.hubURLString = APIClient.shared.baseURLString
        let hostName = Host.current().localizedName ?? "MacBook"
        let _ = try await APIClient.shared.confirmPairing(
            ticket: ticket.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceName: "\(hostName) · macOS",
            deviceModel: "Mac"
        )
        self.isPaired = true
        AudioFeedback.shared.playShutter()
        showTemporaryBanner("配对工单握手成功，凭证已写入本机受保护档案")
        await refreshAll(forceFull: true)
    }

    public func verifyWithMasterPasscode(_ passcode: String, hubURL: String) async throws {
        APIClient.shared.setBaseURL(hubURL)
        self.hubURLString = APIClient.shared.baseURLString
        let hostName = Host.current().localizedName ?? "MacBook"
        let _ = try await APIClient.shared.verifyMasterPasscode(
            passcode: passcode,
            deviceName: "\(hostName) · macOS"
        )
        self.isPaired = true
        AudioFeedback.shared.playShutter()
        showTemporaryBanner("主理人密钥验证通过，本机设备凭证已更新")
        await refreshAll(forceFull: true)
    }

    public func disconnectDevice() {
        CredentialStore.clearAllCredentials()
        self.isPaired = false
        showTemporaryBanner("已清除本机设备配对凭证")
    }

    /// 处理自定义 URL Scheme:
    /// - looseleaf://pair?hub=http://...&ticket=pair_tk_...
    /// - looseleaf://entry/123
    public func handleIncomingURL(_ url: URL) {
        guard url.scheme == "looseleaf" else { return }
        if url.host == "pair" {
            guard let parsed = Self.parsePairLink(url.absoluteString) else { return }
            let hub = parsed.hub.isEmpty ? hubURLString : parsed.hub
            Task { @MainActor in
                do {
                    try await pairWithTicket(parsed.ticket, hubURL: hub)
                } catch {
                    self.errorBanner = error.localizedDescription
                }
            }
        } else if url.host == "entry" {
            if let idStr = url.pathComponents.last, let entryId = Int(idStr),
               let found = entries.first(where: { $0.id == entryId }) {
                self.activeSection = .stream
                self.highlightedEntry = found
            }
        }
    }

    public func showTemporaryBanner(_ text: String) {
        self.statusBanner = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if self.statusBanner == text {
                self.statusBanner = nil
            }
        }
    }
}
