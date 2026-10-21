import Foundation
import SwiftUI
import Observation
import AppKit
#if canImport(ServiceManagement)
import ServiceManagement
#endif

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
/// 侧栏平铺「6 大内容板块 + 5 个配置中心 tab」，不再有二级容器页
public enum WorkbenchSection: String, CaseIterable, Identifiable, Sendable {
    case stream = "stream"       // 时间流 (home)
    case ledger = "ledger"       // 资产 (transactions)
    case wishes = "wishes"       // 心愿 (wishes)
    case atlas = "atlas"         // 足迹 (atlas)
    case projects = "projects"   // 项目 (projects)
    case dossier = "dossier"     // 主理人 (about)
    case preferences = "preferences" // 偏好设置
    case hub = "hub"             // 中枢与设备
    case storage = "storage"     // 存储与备份
    case categories = "categories" // 分类字典
    case about = "about"         // 关于活页

    public var id: String { rawValue }

    /// 六大核心生活内容板块（与 Web HeaderNav 对齐，⌘1–⌘6 绑定到这些）
    public static var contentSections: [WorkbenchSection] {
        [.stream, .ledger, .wishes, .atlas, .projects, .dossier]
    }

    /// 配置类条目：原「配置中心」内部的 5 个 tab，扁平后直接进侧栏
    public static var configurationSections: [WorkbenchSection] {
        [.preferences, .hub, .storage, .categories, .about]
    }

    /// 侧栏平铺的全部条目（内容 + 配置）
    public static var sidebarSections: [WorkbenchSection] {
        contentSections + configurationSections
    }

    public var title: String {
        switch self {
        case .stream: return "时间流"
        case .ledger: return "资产"
        case .wishes: return "心愿"
        case .atlas: return "足迹"
        case .projects: return "项目"
        case .dossier: return "主理人"
        case .preferences: return "偏好设置"
        case .hub: return "中枢与设备"
        case .storage: return "存储与备份"
        case .categories: return "分类字典"
        case .about: return "关于活页"
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
        case .preferences: return "slider.horizontal.3"
        case .hub: return "laptopcomputer.and.iphone"
        case .storage: return "archivebox"
        case .categories: return "tag"
        case .about: return "info.circle"
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

    // MARK: - 导航与交互状态（拆分到独立可观察对象）
    /// 导航与检索状态（独立对象，避免高频交互写入唤醒数据视图）
    public let navigation = AppNavigation()
    /// 瞬时提示状态（独立对象，避免提示条写入唤醒数据视图）
    public let banners = AppBanners()

    public var activeSection: WorkbenchSection {
        get { navigation.activeSection }
        set { navigation.activeSection = newValue }
    }
    public var showNewEntrySheet: Bool = false
    public var newEntryInitialKind: String? {
        get { navigation.newEntryInitialKind }
        set { navigation.newEntryInitialKind = newValue }
    }
    public var newEntryInitialProjectId: Int? {
        get { navigation.newEntryInitialProjectId }
        set { navigation.newEntryInitialProjectId = newValue }
    }
    public var newEntryInitialCityCode: String? {
        get { navigation.newEntryInitialCityCode }
        set { navigation.newEntryInitialCityCode = newValue }
    }
    public var newEntryInitialCityName: String? {
        get { navigation.newEntryInitialCityName }
        set { navigation.newEntryInitialCityName = newValue }
    }
    public var showAlmanacSheet: Bool = false
    public var showStatsSheet: Bool = false
    public var showSearchModal: Bool = false
    public var selectedCategory: ArchiveCategory {
        get { navigation.selectedCategory }
        set { navigation.selectedCategory = newValue }
    }
    public var searchQuery: String {
        get { navigation.searchQuery }
        set { navigation.searchQuery = newValue }
    }
    public var globalSearchResult: GlobalSearchResponse?
    /// 全局检索的加载指示防抖（避免 spinner 闪烁）
    public let globalSearchLoading = LoadingDebouncer()
    public var isGlobalSearching: Bool = false
    public var highlightedEntry: LifeEntry?

    /// 正在编辑的散页（由时间流卡片的「编辑」动作置位）
    ///
    /// 关键：这两个编辑态**必须放在 AppState**（而不是 StreamView 的本地 @State）——
    /// 时间流的行为闭包要能跨视图存续并只捕获 AppState 单例，
    /// 这样闭包集合才能在整轮时间流里保持**同一个引用**，
    /// SwiftUI 才能跳过内容没变的卡片（否则点一下弹窗就要重绘整列 60 张卡）。
    public var editingEntry: LifeEntry?
    /// 正在编辑的账目
    public var editingTransaction: Transaction?
    // MARK: - 时间流卡片行为（放在 AppState 是为了让行为闭包只捕获单例）

    public func toggleFeatured(_ entry: LifeEntry) {
        guard entry.id > 0 else { return }
        let newFeatured = !(entry.featured ?? false)
        Task { @MainActor in
            let req = UpdateEntryRequest(
                type: entry.type,
                title: entry.title,
                content: entry.content,
                occurredAt: entry.occurredAt,
                location: entry.location,
                featured: newFeatured,
                cityCode: entry.cityCode,
                cityName: entry.cityName
            )
            do {
                _ = try await APIClient.shared.updateEntry(id: entry.id, req)
                await self.loadEntries(forceFull: false)
            } catch {
                self.showTemporaryBanner("精选状态更新失败：\(error.localizedDescription)")
            }
        }
    }

    public func deleteEntryAction(_ entry: LifeEntry) {
        guard entry.id > 0 else { return }
        // 登记撤销：删除后可在 5 秒内（或随时按 ⌘Z）恢复该条手稿
        let restoreRequest = CreateEntryRequest(
            type: entry.type,
            title: entry.title,
            content: entry.content,
            occurredAt: entry.occurredAt,
            location: entry.location,
            featured: entry.featured ?? false,
            cityCode: entry.cityCode,
            cityName: entry.cityName,
            projectId: entry.projectId,
            wishId: entry.wishId,
            footprintId: entry.footprintId,
            attachmentIds: entry.attachments.map(\.id)
        )
        Task { @MainActor in
            do {
                _ = try await APIClient.shared.deleteEntry(id: entry.id)
            } catch {
                self.showTemporaryBanner("删除失败：\(error.localizedDescription)")
                return
            }
            await self.loadEntries(forceFull: false)
            await self.loadConfigAndProfile()
            if self.highlightedEntry?.id == entry.id {
                self.highlightedEntry = nil
            }
            self.registerUndo(label: "删除手稿「\(entry.title.isEmpty ? "未命名" : entry.title)」") {
                do {
                    _ = try await APIClient.shared.createEntry(restoreRequest)
                    await self.loadEntries(forceFull: false)
                } catch {
                    self.showTemporaryBanner("撤销失败：\(error.localizedDescription)")
                }
            }
            self.showTemporaryBanner("已删除手稿 · 可按 ⌘Z 撤销")
        }
    }

    public func deleteTransactionAction(_ tx: Transaction) {
        guard tx.id > 0 else { return }
        let restoreRequest = CreateTransactionRequest(
            amount: tx.amount,
            type: tx.type,
            category: tx.category,
            title: tx.title,
            note: tx.note,
            paymentMethod: tx.paymentMethod,
            cityCode: tx.cityCode,
            occurredAt: tx.occurredAt
        )
        Task { @MainActor in
            do {
                _ = try await APIClient.shared.deleteTransaction(id: tx.id)
            } catch {
                self.showTemporaryBanner("删除账目失败：\(error.localizedDescription)")
                return
            }
            await self.loadTransactionsAndAssets(forceFull: false)
            await self.loadEntries(forceFull: false)
            await self.loadConfigAndProfile()
            if self.highlightedEntry?.id == tx.id {
                self.highlightedEntry = nil
            }
            self.registerUndo(label: "删除账目「\(tx.title.isEmpty ? tx.category : tx.title)」") {
                do {
                    _ = try await APIClient.shared.createTransaction(restoreRequest)
                    await self.loadTransactionsAndAssets(forceFull: false)
                } catch {
                    self.showTemporaryBanner("撤销失败：\(error.localizedDescription)")
                }
            }
            self.showTemporaryBanner("已删除账目 · 可按 ⌘Z 撤销")
        }
    }

    /// 在**独立窗口**中打开的条目（深链 / 「在新窗口打开」使用，与主窗口的弹层互不影响）
    public var detailWindowEntry: LifeEntry?

    /// 接力活动类型（与 Info.plist 的 NSUserActivityTypes 对应）
    public static let userActivityType = "com.looseleaf.entry"
    /// 当前接力活动（把最近浏览的散页暴露给其它设备接力）
    private var currentUserActivity: NSUserActivity?
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
    public var statusBanner: String? {
        get { banners.status }
        set { banners.status = newValue }
    }
    public var errorBanner: String? {
        get { banners.error }
        set { banners.error = newValue }
    }
    /// 本地档案完整性问题（快照解码失败等），优先级高于普通网络错误，需用户手动关闭
    public var localDataWarning: String? {
        get { banners.localWarning }
        set { banners.localWarning = newValue }
    }

    public var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "looseleaf_appearance_mode")
        }
    }

    public var globalHotkeyLabel: String { AppDelegate.hotKeyDisplayName }

    /// ⌘F 请求时间流搜索框聚焦（自增 token 驱动 onChange）
    public var searchFocusRequest: Int {
        get { navigation.searchFocusRequest }
        set { navigation.searchFocusRequest = newValue }
    }

    // MARK: - 偏好：Dock 图标与登录启动

    /// 是否在 Dock 中显示应用图标（常驻菜单栏型应用可关闭以释放 Dock 位置）
    public var showsDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showsDockIcon, forKey: "looseleaf_shows_dock_icon")
            applyActivationPolicy()
        }
    }

    /// 是否在登录时自动启动
    public var launchesAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchesAtLogin, forKey: "looseleaf_launches_at_login")
            applyLaunchAtLogin()
        }
    }

    /// 是否启用触感反馈
    public var enablesHapticFeedback: Bool {
        didSet {
            UserDefaults.standard.set(enablesHapticFeedback, forKey: "looseleaf_enables_haptic_feedback")
        }
    }

    /// 是否在同步完成 / 失败时发送系统通知
    public var notifiesOnSync: Bool {
        didSet {
            UserDefaults.standard.set(notifiesOnSync, forKey: "looseleaf_notifies_on_sync")
        }
    }

    /// UI 测试用中枢地址（启动参数 `-UITestHubURL <url>` 或环境变量 `LOOSELEAF_HUB_URL`）
    nonisolated static var uiTestHubURL: String? {
        if let idx = CommandLine.arguments.firstIndex(of: "-UITestHubURL"),
           idx + 1 < CommandLine.arguments.count {
            return CommandLine.arguments[idx + 1]
        }
        if let env = ProcessInfo.processInfo.environment["LOOSELEAF_HUB_URL"], !env.isEmpty {
            return env
        }
        return nil
    }

    /// 冷启动引导是否已执行（防止重复拉取）
    @ObservationIgnored private var hasBootstrapped: Bool = false

    /// 当前是否存在需要关闭的自定义浮层（供 ⌘W 菜单项启用/禁用）
    public var hasOpenOverlay: Bool {
        activeConfirmDialog != nil
            || showSearchModal
            || showStatsSheet
            || showNewEntrySheet
            || lightboxAttachment != nil
    }

    public func requestStreamSearchFocus() {
        navigation.requestStreamSearchFocus()
    }

    // MARK: - 派生数据记忆缓存（@ObservationIgnored：写入不触发视图更新）
    /// 仅在「条目/账目」集合变化时自增；配置类变更不应让列表 memo 全部失效
    @ObservationIgnored private var entriesRevision: Int = 0
    @ObservationIgnored private var filteredMemo: (key: String, value: [LifeEntry])?
    @ObservationIgnored private var streamRowsMemo: (key: String, value: [StreamRow])?
    @ObservationIgnored private var entryCountsMemo: (key: String, value: [String: Int])?
    /// 账目索引（id -> 账目）：时间流卡片按 id 查账目时避免全量遍历
    @ObservationIgnored private var transactionIndexMemo: (Int, [Int: Transaction])?
    /// 全局检索代号：防止先发出的慢请求覆盖后发出的快请求结果
    @ObservationIgnored private var globalSearchGeneration: UInt64 = 0

    private init() {
        let savedAppearance = UserDefaults.standard.string(forKey: "looseleaf_appearance_mode") ?? AppearanceMode.system.rawValue
        self.appearanceMode = AppearanceMode(rawValue: savedAppearance) ?? .system

        // UI 自动化测试钩子：允许用启动参数把中枢指向本地实例，
        // 使测试可以自由造数据而不污染真实中枢。
        if let hubURL = Self.uiTestHubURL {
            APIClient.shared.setBaseURL(hubURL)
        }

        self.isPaired = (CredentialStore.getToken()?.isEmpty == false)
        self.showsDockIcon = UserDefaults.standard.object(forKey: "looseleaf_shows_dock_icon") as? Bool ?? true
        self.launchesAtLogin = UserDefaults.standard.object(forKey: "looseleaf_launches_at_login") as? Bool ?? false
        self.notifiesOnSync = UserDefaults.standard.object(forKey: "looseleaf_notifies_on_sync") as? Bool ?? true
        self.enablesHapticFeedback = UserDefaults.standard.object(forKey: "looseleaf_enables_haptic_feedback") as? Bool ?? true

        // 1. 毫秒级载入本地持久化快照 (Local-First 0ms 白屏)
        self.isOnline = SyncManager.shared.isOnline
        self.isFlushingOutbox = SyncManager.shared.isFlushingOutbox

        // 2. 先注册回调，再读取快照：若后台解码已完成则直接拿到完整快照，
        //    否则后续 onSnapshotUpdated 回调会把注水后的快照推给 UI（两条路径都覆盖）。
        // 关键：这三个回调**同步**应用，不要包一层 Task。
        // SyncManager 与 AppState 同在 MainActor，直接调用即可；
        // 若经 Task 派发，乐观写入的条目要等到下一个 runloop 才出现在时间流里 ——
        // 这正是「提交后感觉慢了一拍」的来源之一。
        SyncManager.shared.onSnapshotUpdated = { [weak self] snap in
            guard let self else { return }
            self.isOnline = SyncManager.shared.isOnline
            self.isFlushingOutbox = SyncManager.shared.isFlushingOutbox
            self.applySnapshot(snap)
        }

        SyncManager.shared.onLocalDataWarning = { [weak self] message in
            self?.localDataWarning = message
        }

        SyncManager.shared.onNetworkStatusChanged = { [weak self] online in
            self?.isOnline = online
        }

        applySnapshot(SyncManager.shared.currentSnapshot())

        // 本地快照解码失败时必须在首屏明确告警，绝不能让用户以为"数据只是变少了"
        if let failure = SyncManager.shared.lastLoadFailureMessage {
            self.localDataWarning = failure
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
        // 相等性判断：@Observable 的 setter 无论值是否相等都会触发全树重渲染，
        // 因此必须先比较再赋值，把「每次同步全量重绘」降级为「仅真正变化时重绘」。
        let entriesChanged = self.entries != snap.entries
        let transactionsChanged = self.transactions != snap.transactions
        if entriesChanged { self.entries = snap.entries }
        if transactionsChanged { self.transactions = snap.transactions }
        if self.transactionSummary != snap.transactionSummary { self.transactionSummary = snap.transactionSummary }
        if self.profile != snap.profile { self.profile = snap.profile }
        if self.siteConfig != snap.siteConfig { self.siteConfig = snap.siteConfig }
        if self.stats != snap.stats { self.stats = snap.stats }
        if self.outboxItems != snap.outbox { self.outboxItems = snap.outbox }
        if entriesChanged || transactionsChanged {
            entriesRevision += 1
        }
        // 系统搜索索引（Spotlight，异步派发不阻塞渲染）
        // 关键：仅在条目**真正变化**时才重建索引 ——
        // 只改了配置/统计时也全量 diff 会白做一次 O(N) 遍历与指纹计算。
        if entriesChanged {
            SpotlightIndexer.reindex(entries: snap.entries)
        }
    }

    // MARK: - 过滤与检索计算属性

    /// 供主窗口展示的过滤后时间流列表（融合账目视角、分类过滤、#标签下钻与模糊搜索）
    /// 带记忆缓存：仅在数据版本或筛选条件变化时重算，渲染路径零重复过滤
    public var filteredStreamEntries: [LifeEntry] {
        let key = "\(entriesRevision)|\(selectedCategory.rawValue)|\(searchQuery)"
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

    // 账目 id → 账目 的索引（按 entriesRevision 记忆化）
    /// 关键：时间流卡片原先在 body 里对每个条目做 `transactions.first(where:)`，
    /// N 行 × M 条账目 = O(N×M)；现在一次建表，查询 O(1)。
    public var transactionById: [Int: Transaction] {
        if let memo = transactionIndexMemo, memo.0 == entriesRevision {
            return memo.1
        }
        var map: [Int: Transaction] = [:]
        map.reserveCapacity(transactions.count)
        for tx in transactions { map[tx.id] = tx }
        transactionIndexMemo = (entriesRevision, map)
        return map
    }

    /// 已算好间隔的时间流（带记忆缓存）：避免渲染时每行重复解析两次时间戳
    public var streamRows: [StreamRow] {
        let key = "\(entriesRevision)|\(selectedCategory.rawValue)|\(searchQuery)"
        if let memo = streamRowsMemo, memo.key == key {
            return memo.value
        }
        ArchivePerformance.mark(.render, "streamRows.recompute")
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
            // 清空查询时让所有在途请求失效，避免旧结果稍后回填
            globalSearchGeneration &+= 1
            self.globalSearchResult = nil
            self.isGlobalSearching = false
            return
        }
        // 代号机制：快速输入「咖 → 咖啡」时，先发出的「咖」请求可能后返回；
        // 只允许最新代号的结果写入 UI，旧结果直接丢弃。
        globalSearchGeneration &+= 1
        let generation = globalSearchGeneration
        self.isGlobalSearching = true
        globalSearchLoading.begin()
        defer {
            if generation == globalSearchGeneration {
                self.isGlobalSearching = false
            }
            globalSearchLoading.end()
        }
        do {
            let res = try await APIClient.shared.searchGlobalArchive(query: q, limit: 30)
            guard generation == globalSearchGeneration, !Task.isCancelled else { return }
            self.globalSearchResult = res
        } catch {
            // 网络受阻或离线时保持本地纯粹搜索
        }
    }

    /// 按北京时间自然日聚合的记录密度（52 周热力图数据源，带记忆缓存）
    public var entryCountsByDate: [String: Int] {
        let key = "\(entriesRevision)"
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

    /// 应用冷启动引导：全量刷新 + 检查更新。
    /// 关键：触发点从「视图 .task」迁移到 App 生命周期，
    /// 否则主窗口与子视图各挂一次 `.task` 会重复发起整套拉取。
    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await refreshAll()
        await UpdateChecker.shared.checkForUpdates(isUserInitiated: false)
    }

    public func refreshAll(forceFull: Bool = false) async {
        // 启动期主窗口与子视图可能各触发一次；并发执行只会重复请求并互相冲刷快照。
        // 但直接 return 会让用户按 ⌘R 时毫无反馈，误以为快捷键失效。
        guard !isLoading else {
            showTemporaryBanner("正在同步档案，请稍候…")
            return
        }
        isLoading = true
        errorBanner = nil
        defer { isLoading = false }

        // 先尝试排空离线发件箱；用户主动「全量同步」时把暂停的死信重新入队。
        if forceFull {
            SyncManager.shared.resetPausedOutboxItems()
        }
        await SyncManager.shared.flushOutbox()

        // 批量模式：5 个并发任务各自会写快照，若每次都立即回调 UI，
        // 会造成 5 次整页重绘；批次结束后统一回调一次。
        SyncManager.shared.beginBatch()
        defer { SyncManager.shared.endBatch() }

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

    /// 「首屏只投递一次」的一次性闸门（跨隔离域安全）
    private final class FirstPageGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        /// 尝试抢占；只有第一个调用者返回 true
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

    public func loadEntries(forceFull: Bool = false) async {
        let snap = SyncManager.shared.currentSnapshot()
        // 关键保障：若本地 entries 尚为空，必须强制全量拉取，杜绝因残留 cursor 导致拉取空增量！
        let cursor = (forceFull || snap.entries.isEmpty) ? nil : snap.lastEntriesSyncCursor
        do {
            // 首屏优先：第一页一到就先把内容铺到界面上，
            // 剩余页在后台继续拉取并追加，用户无需等待全量同步完成。
            // 用一次性原子盒记录「是否已投递首屏」——闭包会跨隔离域执行，
            // 直接捕获可变局部变量在 Swift 6 下不安全。
            let firstPageGate = FirstPageGate()
            let allFetched = try await Pagination.fetchAllEntries(
                since: cursor,
                pageSize: 100,
                useETagOnFirstPage: !forceFull && cursor == nil
            ) { _, firstPage in
                guard firstPageGate.claim(), !firstPage.isEmpty else { return }
                await MainActor.run {
                    SyncManager.shared.mergeEntries(firstPage, isDelta: cursor != nil)
                }
            }
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

    /// 二级对象（心愿 / 器物 / 账目 / 足迹 / 造物）写操作后的**统一刷新**。
    ///
    /// 关键：这些对象在服务端都会落一条**伴生 LifeEntry**（时间流的一级数据），
    /// 若只刷新二级集合，时间流就看不到变化 —— 这正是「创建心愿后时间流没反应」的原因。
    /// 这里同时做一次**增量**拉取（带 cursor），把伴生散页并进时间流。
    public func refreshAfterSecondaryWrite() async {
        await loadProjectsWishesFootprints()
        await loadEntries(forceFull: false)
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

        // 乐观更新：账目立刻出现在账本与时间流，后台静默同步
        SyncManager.shared.submitTransactionInBackground(req)
        showTemporaryBanner("已记入账本：\(FormatUtils.formattedYuan(cents: amountCents, includeSymbol: true))")
        Task { @MainActor in
            await loadTransactionsAndAssets(forceFull: false)
            await loadConfigAndProfile()
        }
        return false
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
            self.detailWindowEntry = found
            publishHandoffActivity(for: found)
        } else {
            // 若当前本地快照中尚未载入该条目，异步刷新后再次尝试查找
            Task { @MainActor in
                await self.loadEntries(forceFull: true)
                if let found = self.entries.first(where: { $0.id == entryId }) {
                    self.detailWindowEntry = found
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

    // MARK: - Dock 图标策略与登录启动

    /// 应用激活策略：.regular 显示在 Dock 与 ⌘Tab；.accessory 只驻留菜单栏
    private func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = showsDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    /// 登录时启动（macOS 13+ 使用 SMAppService 主应用注册）
    private func applyLaunchAtLogin() {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if launchesAtLogin {
                    if service.status != .enabled {
                        try service.register()
                    }
                } else {
                    if service.status == .enabled {
                        try service.unregister()
                    }
                }
            } catch {
                showTemporaryBanner("登录启动设置失败：\(error.localizedDescription)")
            }
        }
        #endif
    }

    // MARK: - 接力 (Handoff / NSUserActivity)

    /// 把某条散页发布为当前接力活动（其它 Mac / iPhone 可在同一 Apple ID 下接力继续浏览）
    public func publishHandoffActivity(for entry: LifeEntry) {
        let activity = NSUserActivity(activityType: Self.userActivityType)
        // NSUserActivity 没有 subtitle；地点信息并入 title 的说明文案
        let baseTitle = entry.title.isEmpty ? "散页手稿" : entry.title
        if let place = entry.cityName ?? entry.location, !place.isEmpty {
            activity.title = "\(baseTitle) · \(place)"
        } else {
            activity.title = baseTitle
        }
        activity.userInfo = ["entryId": entry.id]
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.becomeCurrent()
        currentUserActivity = activity
    }

    /// 结束接力活动
    public func endHandoffActivity() {
        currentUserActivity?.resignCurrent()
        currentUserActivity = nil
    }

    /// 处理接力过来的活动（来自其它设备的「继续浏览」）
    public func handleHandoffActivity(_ activity: NSUserActivity) {
        guard activity.activityType == Self.userActivityType else { return }
        let raw = activity.userInfo?["entryId"] as? NSNumber
        let id = raw?.intValue ?? activity.userInfo?["entryId"] as? Int ?? -1
        guard id >= 0 else { return }
        navigateToEntry(id: id)
    }

    // MARK: - 同步失败重试

    /// 重试一条标记为 failed 的散页
    public func retryFailedEntry(id: Int) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let req = CreateEntryRequest(
            type: entry.type,
            title: entry.title,
            content: entry.content,
            occurredAt: entry.occurredAt,
            location: entry.location,
            featured: entry.featured ?? false,
            cityCode: entry.cityCode,
            cityName: entry.cityName,
            projectId: entry.projectId,
            wishId: entry.wishId,
            footprintId: entry.footprintId,
            attachmentIds: entry.attachments.map(\.id)
        )
        // 先把状态改回待同步，让用户立刻看到反馈
        SyncManager.shared.markEntryRetrying(id: id)
        SyncManager.shared.submitEntryInBackground(req, attachments: entry.attachments)
    }

    /// 重试一条标记为 failed 的账目
    public func retryFailedTransaction(id: Int) {
        guard let tx = transactions.first(where: { $0.id == id }) else { return }
        let req = CreateTransactionRequest(
            amount: tx.amount,
            type: tx.type,
            category: tx.category,
            title: tx.title,
            note: tx.note,
            paymentMethod: tx.paymentMethod,
            cityCode: tx.cityCode,
            occurredAt: tx.occurredAt
        )
        SyncManager.shared.markTransactionRetrying(id: id)
        SyncManager.shared.submitTransactionInBackground(req)
    }

    // MARK: - 撤销栈 (Undo)

    /// 一次可撤销的操作
    public struct UndoAction: Identifiable {
        public let id = UUID()
        public let label: String
        let perform: () async -> Void

        public init(label: String, perform: @escaping () async -> Void) {
            self.label = label
            self.perform = perform
        }
    }

    /// 最近的撤销操作（栈顶为最近一次）
    @ObservationIgnored private var undoStack: [UndoAction] = []
    /// 撤销栈容量上限
    public static let maxUndoStackSize = 20

    /// 是否存在可撤销的操作（供菜单项启用/禁用）
    public var canUndo: Bool { !undoStack.isEmpty }

    /// 最近一次可撤销操作的名称（供界面展示）
    public var undoActionLabel: String? { undoStack.last?.label }

    /// 登记一次可撤销操作
    public func registerUndo(label: String, perform: @escaping () async -> Void) {
        undoStack.append(UndoAction(label: label, perform: perform))
        if undoStack.count > Self.maxUndoStackSize {
            undoStack.removeFirst(undoStack.count - Self.maxUndoStackSize)
        }
    }

    /// 执行并弹出最近一次撤销操作
    public func performUndo() async {
        guard let action = undoStack.popLast() else { return }
        await action.perform()
        showTemporaryBanner("已撤销「\(action.label)」")
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
