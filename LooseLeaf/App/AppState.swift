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

/// 桌面端主窗口侧栏导航模块 (对标 Web HeaderNav 6 大平级主视图)
public enum WorkbenchSection: String, CaseIterable, Identifiable, Sendable {
    case stream = "stream"       // 时间流 (home)
    case ledger = "ledger"       // 资产 (transactions)
    case wishes = "wishes"       // 心愿 (wishes)
    case atlas = "atlas"         // 足迹 (atlas)
    case projects = "projects"   // 项目 (projects)
    case dossier = "dossier"     // 主理人 (about)
    case settings = "settings"   // 配置中心 (settings)
    case darkroom = "darkroom"   // 辅助：银盐暗房

    public var id: String { rawValue }

    /// 侧边栏纯粹呈现 Web 6 大核心生活内容板块
    public static var sidebarSections: [WorkbenchSection] {
        [.stream, .ledger, .wishes, .atlas, .projects, .dossier]
    }

    public var title: String {
        switch self {
        case .stream: return "时间流"
        case .ledger: return "资产"
        case .wishes: return "心愿"
        case .atlas: return "足迹"
        case .projects: return "项目"
        case .dossier: return "主理人"
        case .settings: return "配置中心"
        case .darkroom: return "银盐暗房"
        }
    }

    public var icon: String {
        switch self {
        case .stream: return "book.pages"
        case .ledger: return "chart.bar.doc.horizontal"
        case .wishes: return "sparkles"
        case .atlas: return "map"
        case .projects: return "hammer"
        case .dossier: return "person.text.rectangle"
        case .settings: return "gearshape"
        case .darkroom: return "camera.aperture"
        }
    }
}

/// 极速捕捉模式选项 (极速记录 / 快速记账)
public enum QuickCaptureTab: String, CaseIterable, Sendable {
    case thought = "极速记录"
    case ledger = "快速记账"
}

/// 跨窗口持久化快速捕捉草稿容器 (@Observable)
/// 统一 MenuBar 与悬浮窗状态实例，消除草稿割裂
@Observable
@MainActor
public final class QuickCaptureDraft {
    public var activeTab: QuickCaptureTab = .thought
    public var entryType: EntryType = .life
    public var titleText: String = ""
    public var contentText: String = ""
    public var customLocation: String = ""
    public var selectedCityCode: String = ""
    public var selectedCityName: String = ""
    public var isFeatured: Bool = false
    public var uploadedAttachments: [Attachment] = []
    public var extractedCameraLine: String = ""
    public var occurredAt: Date = Date()
    public var showBackdatePicker: Bool = false

    public func reset() {
        titleText = ""
        contentText = ""
        customLocation = ""
        selectedCityCode = ""
        selectedCityName = ""
        uploadedAttachments.removeAll()
        extractedCameraLine = ""
        isFeatured = false
        occurredAt = Date()
        showBackdatePicker = false
    }
}

/// 全局纸本确认与警示对话框请求 (对标 Web useConfirm.ts / ConfirmDialog.vue)
public struct ConfirmDialogRequest: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String
    public var confirmText: String
    public var cancelText: String
    public var danger: Bool
    public var onConfirm: () -> Void
    public var onCancel: (() -> Void)?

    public init(
        title: String = "请确认",
        message: String,
        confirmText: String = "确认",
        cancelText: String = "取消",
        danger: Bool = true,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.confirmText = confirmText
        self.cancelText = cancelText
        self.danger = danger
        self.onConfirm = onConfirm
        self.onCancel = onCancel
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
    public var onThisDayEntries: [LifeEntry] = []

    // MARK: - 动态分类字典 (由 /api/v1/categories 下发驱动)
    public var expenseCategories: [String] = ["餐饮", "交通", "购物", "数码器材", "娱乐", "学习", "住房", "医疗", "旅行度假", "其他"]
    public var incomeCategories: [String] = ["工资收入", "二手回血", "稿酬设计", "投资理财", "礼金红包", "退款报销", "其他收入"]
    public var gearCategories: [String] = ["数码器材", "影像与暗房", "工作台与算力", "手冲咖啡工坊", "夜骑巡航", "纸笔与日常", "生活好物"]
    public var projectCategories: [String] = ["开源项目", "独立开发", "硬件改造", "设计作品", "写作出版"]
    public var paymentMethods: [String] = ["微信支付", "支付宝", "银行卡", "现金", "其他"]

    // MARK: - 导航与交互状态
    public var activeSection: WorkbenchSection = .stream
    public var showNewEntrySheet: Bool = false
    public var newEntryInitialKind: String? = nil
    public var newEntryInitialProjectId: Int? = nil
    public var newEntryInitialCityCode: String? = nil
    public var newEntryInitialCityName: String? = nil
    public var showAlmanacSheet: Bool = false
    public var showStatsSheet: Bool = false
    public var showSearchModal: Bool = false
    public var selectedCategory: ArchiveCategory = .all
    public var searchQuery: String = ""
    public var globalSearchResult: GlobalSearchResponse?
    public var isGlobalSearching: Bool = false
    public var highlightedEntry: LifeEntry?
    public var lightboxAttachment: Attachment?
    public var activeConfirmDialog: ConfirmDialogRequest? = nil

    /// 统一纸墨风格确认弹窗交互 (替代系统原生 confirmationDialog / alert)
    public func askConfirm(
        title: String = "请确认",
        message: String,
        confirmText: String = "确认",
        cancelText: String = "取消",
        danger: Bool = true,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        activeConfirmDialog = ConfirmDialogRequest(
            title: title,
            message: message,
            confirmText: confirmText,
            cancelText: cancelText,
            danger: danger,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }

    public func dismissConfirm() {
        activeConfirmDialog?.onCancel?()
        activeConfirmDialog = nil
    }

    /// 键盘流（⌘↑ / ⌘↓）当前聚焦的时间流条目 ID
    public var keyboardFocusedEntryId: Int?

    /// 系统「服务」菜单摘录的待归档文本（QuickCaptureView 消费后清空）
    public var pendingCaptureText: String?

    /// 跨窗口持久化快速捕捉草稿中心（MenuBar 与 ⌘⇧L 悬浮窗实时共享）
    public var quickDraft: QuickCaptureDraft = QuickCaptureDraft()

    // MARK: - 鉴权、网络与偏好设置状态
    public var isPaired: Bool = false
    public var hubURLString: String = APIClient.shared.baseURLString
    public var isLoading: Bool = false
    public var isOnline: Bool = true
    public var isFlushingOutbox: Bool = false
    public var statusBanner: String?
    public var errorBanner: String?
    /// 本地档案完整性问题（快照解码失败等），优先级高于普通网络错误，需用户手动关闭
    public var localDataWarning: String?

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
    @ObservationIgnored private var streamRowsMemo: (key: String, value: [StreamRow])?
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

        // 本地快照解码失败时必须在首屏明确告警，绝不能让用户以为"数据只是变少了"
        if let failure = SyncManager.lastLoadFailureMessage {
            self.localDataWarning = failure
        }

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
        let key = "\(dataRevision)|\(selectedCategory.rawValue)|\(searchQuery)"
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

    /// 时间流行模型：条目 + 与上一条的自然日间隔（用于 14 天留白切线）
    public struct StreamRow: Identifiable, Sendable {
        public let entry: LifeEntry
        public let gapDays: Int
        public var id: Int { entry.id }
    }

    /// 已算好间隔的时间流（带记忆缓存）：避免渲染时每行重复解析两次时间戳
    public var streamRows: [StreamRow] {
        let key = "\(dataRevision)|\(selectedCategory.rawValue)|\(searchQuery)"
        if let memo = streamRowsMemo, memo.key == key {
            return memo.value
        }
        let list = filteredStreamEntries
        var rows: [StreamRow] = []
        rows.reserveCapacity(list.count)
        for (index, entry) in list.enumerated() {
            let gap = index == 0
                ? 0
                : FormatUtils.daysBetween(list[index - 1].occurredAt, entry.occurredAt)
            rows.append(StreamRow(entry: entry, gapDays: gap))
        }
        streamRowsMemo = (key, rows)
        return rows
    }

    /// 全库跨模块网络搜索（当已配对时发起，支持足迹、心愿与造物项目联动检索）
    public func performGlobalSearch(query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, isPaired else {
            self.globalSearchResult = nil
            return
        }
        self.isGlobalSearching = true
        defer { self.isGlobalSearching = false }
        do {
            let res = try await APIClient.shared.searchGlobalArchive(query: q, limit: 30)
            self.globalSearchResult = res
        } catch {
            // 网络受阻或离线时保持本地纯粹搜索
        }
    }

    /// 按北京时间自然日聚合的记录密度（52 周热力图数据源，带记忆缓存）
    public var entryCountsByDate: [String: Int] {
        let key = "\(dataRevision)"
        if let memo = entryCountsMemo, memo.key == key {
            return memo.value
        }
        var counts: [String: Int] = [:]
        for entry in entries {
            let parsed = entry.parsedDate
            guard parsed.isValid else { continue }
            counts[parsed.dateKey, default: 0] += 1
        }
        entryCountsMemo = (key, counts)
        return counts
    }

    // MARK: - 远端全量与增量拉取

    public func refreshAll(forceFull: Bool = false) async {
        // 启动期主窗口与子视图可能各触发一次；并发执行只会重复请求并互相冲刷快照
        guard !isLoading else { return }
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
        let inc = list.filter { $0.scope == "income" }.map(\.name)
        if !inc.isEmpty {
            self.incomeCategories = inc
        }
        let gear = list.filter { $0.scope == "gear" }.map(\.name)
        if !gear.isEmpty {
            self.gearCategories = gear
        }
        let proj = list.filter { $0.scope == "project" }.map(\.name)
        if !proj.isEmpty {
            self.projectCategories = proj
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
            let allFetched = try await Pagination.fetchAllEntries(
                since: cursor,
                pageSize: 100,
                useETagOnFirstPage: !forceFull && cursor == nil
            )
            SyncManager.shared.mergeEntries(allFetched, isDelta: cursor != nil)
        } catch APIError.notModified {
            // 304 Not Modified: 本地缓存已是最新
        } catch {
            if entries.isEmpty {
                self.errorBanner = error.localizedDescription
            }
        }

        if let otd = try? await APIClient.shared.fetchOnThisDayEntries() {
            self.onThisDayEntries = otd.entries
        }
    }

    public func loadTransactionsAndAssets(forceFull: Bool = false) async {
        guard isPaired else { return }
        let snap = SyncManager.shared.currentSnapshot()
        let cursor = (forceFull || snap.transactions.isEmpty) ? nil : snap.lastTransactionsSyncCursor

        do {
            let allTxs = try await Pagination.fetchAllTransactions(
                since: cursor,
                batchLimit: 500,
                useETagOnFirstBatch: !forceFull && cursor == nil
            )
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
        // 只有"确实成功拉到数据"才覆盖；空数组是合法结果（删掉最后一枚心愿也必须生效）
        if let allWishes = try? await Pagination.fetchAllWishes() {
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
        cityCode: String? = nil,
        cityName: String? = nil,
        attachmentIds: [Int] = [],
        featured: Bool = false,
        occurredAt: String? = nil
    ) async throws -> Bool {
        let finalLocation = (location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? location!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (profile.displayCity.isEmpty ? nil : profile.displayCity)

        var resolvedCode = cityCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedCode?.isEmpty == true { resolvedCode = nil }
        var resolvedCityName = cityName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedCityName?.isEmpty == true { resolvedCityName = nil }

        if resolvedCode == nil, let loc = finalLocation {
            resolvedCode = FormatUtils.resolveCityCode(from: loc)
        }
        if resolvedCode != nil && resolvedCityName == nil {
            resolvedCityName = CityDictionary.standardCities.first(where: { $0.code == resolvedCode })?.name
        }

        let req = CreateEntryRequest(
            type: type.rawValue,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            occurredAt: occurredAt ?? FormatUtils.beijingISOString(),
            location: finalLocation,
            featured: featured,
            cityCode: resolvedCode,
            cityName: resolvedCityName,
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
        paymentMethod: String? = nil,
        cityCode: String? = nil,
        occurredAt: String? = nil
    ) async throws -> Bool {
        let req = CreateTransactionRequest(
            amount: amountCents,
            type: type,
            category: category,
            title: title,
            note: note,
            paymentMethod: paymentMethod ?? paymentMethods.first ?? "微信支付",
            cityCode: cityCode,
            occurredAt: occurredAt ?? FormatUtils.beijingISOString()
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

    public func disconnectDevice() async {
        if let devId = CredentialStore.getDeviceId() {
            try? await APIClient.shared.revokeDevice(id: devId)
        }
        CredentialStore.clearAllCredentials()
        self.isPaired = false
        showTemporaryBanner("已安全吊销并清除本机设备配对凭证")
    }

    /// 导航定位并打开指定散页（Spotlight 系统搜索 / 深链直达）
    public func navigateToEntry(id entryId: Int) {
        self.activeSection = .stream
        self.selectedCategory = .all
        self.searchQuery = ""
        self.keyboardFocusedEntryId = entryId

        if let found = entries.first(where: { $0.id == entryId }) {
            self.highlightedEntry = found
            AudioFeedback.shared.playPaperFlip()
        } else {
            // 若当前本地快照中尚未载入该条目，异步刷新后再次尝试查找
            Task { @MainActor in
                await self.loadEntries(forceFull: true)
                if let found = self.entries.first(where: { $0.id == entryId }) {
                    self.highlightedEntry = found
                    AudioFeedback.shared.playPaperFlip()
                }
            }
        }
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
            if let idStr = url.pathComponents.last, let entryId = Int(idStr) {
                navigateToEntry(id: entryId)
            }
        }
    }

    public func showTemporaryBanner(_ text: String) {
        self.statusBanner = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            if self.statusBanner == text {
                self.statusBanner = nil
            }
        }
    }
}
