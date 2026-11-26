import Foundation
import SwiftUI
import Observation
import AppKit
import os
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// 全局响应式状态中心 (@Observable)
/// 遵循本地优先 (Local-First) 毫秒级上屏 + 后台异步增量同步架构
/// 子职责按扩展拆分为：
/// - `AppStateTypes.swift`：导航板块、外观、连接徽标、极速草稿与弹窗请求类型
/// - `AppState+StreamProjection.swift`：时间流筛选、分组间隔、检索语料与键盘聚焦
/// - `AppState+Pairing.swift`：配对握手、解绑全清、深链与 Handoff 接力
/// - `AppState+UndoAndActions.swift`：⌘Z 撤销栈、增删动作、快速捕捉提交与待发重传
@Observable
@MainActor
public final class AppState {
    public static let shared = AppState()
    static let logger = Logger(subsystem: "com.looseleaf.mac", category: "appstate")

    // MARK: - 核心业务数据 (100% 动态驱动，严禁假数据兜底)
    public var entries: [LifeEntry] = [] {
        didSet {
            entriesRevision += 1
            onThisDayCacheDateKey = nil
            recomputeUploadCounts()
        }
    }
    public var transactions: [Transaction] = [] {
        didSet {
            transactionsRevision += 1
            recomputeUploadCounts()
        }
    }
    public var transactionSummary: TransactionSummary = TransactionSummary()
    public var profile: CuratorProfile = CuratorProfile()
    public var siteConfig: SiteConfig = SiteConfig()
    public var stats: GlobalStats = GlobalStats()
    public var wishes: [Wish] = []
    public var trustedDevices: [TrustedDevice] = []
    public var creditChannels: [CreditChannel] = []
    public var outboxItems: [OutboxItem] = []
    public var onThisDayEntries: [LifeEntry] = []

    // MARK: - 动态分类字典 (由 /api/v1/categories 下发驱动)
    public var expenseCategories: [String] = ["餐饮", "交通", "购物", "数码器材", "娱乐", "学习", "住房", "医疗", "旅行度假", "其他"]
    public var incomeCategories: [String] = ["工资收入", "二手回血", "稿酬设计", "投资理财", "礼金红包", "退款报销", "其他收入"]
    public var paymentMethods: [String] = ["微信支付", "支付宝", "银行卡", "现金", "其他"]

    // MARK: - 导航与交互状态（拆分到独立可观察对象）
    public let navigation = AppNavigation()
    public let banners = AppBanners()

    public var activeSection: WorkbenchSection {
        get { navigation.activeSection }
        set { navigation.activeSection = newValue }
    }
    public var showNewEntrySheet: Bool = false
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
    public internal(set) var globalSearchResultVersion: Int = 0
    public let globalSearchLoading = LoadingDebouncer()
    public var isGlobalSearching: Bool = false
    public var highlightedEntry: LifeEntry?
    public var editingEntry: LifeEntry?
    public var editingTransaction: Transaction?
    public var detailWindowEntry: LifeEntry?

    /// 接力活动类型（与 Info.plist 的 NSUserActivityTypes 对应）
    public static let userActivityType = "com.looseleaf.entry"
    var currentUserActivity: NSUserActivity?
    public var lightboxAttachment: Attachment?
    public var activeConfirmDialog: ConfirmDialogRequest? = nil
    public var keyboardFocusedEntryId: Int?
    public var pendingCaptureText: String?
    public var quickDraft: QuickCaptureDraft = QuickCaptureDraft()

    // MARK: - 鉴权、网络与偏好设置状态
    public var isPaired: Bool = false
    public var accountName: String = ""
    public var accountEmail: String = ""
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
    public var localDataWarning: String? {
        get { banners.localWarning }
        set { banners.localWarning = newValue }
    }

    public var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "looseleaf_appearance_mode")
            applyAppAppearance()
        }
    }

    public func applyAppAppearance() {
        guard let app = NSApp else { return }
        switch appearanceMode {
        case .system:
            app.appearance = nil
        case .paper:
            app.appearance = NSAppearance(named: .aqua)
        case .darkroom:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    public func openSettings(tab: SettingsTab = .general) {
        navigation.settingsSelectedTab = tab
        navigation.settingsOpenToken &+= 1
    }

    public var searchFocusRequest: Int {
        get { navigation.searchFocusRequest }
        set { navigation.searchFocusRequest = newValue }
    }

    // MARK: - 偏好：Dock 图标、登录启动与 Spotlight 隐私

    public var showsDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showsDockIcon, forKey: "looseleaf_shows_dock_icon")
            applyActivationPolicy()
        }
    }

    public var launchesAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchesAtLogin, forKey: "looseleaf_launches_at_login")
            applyLaunchAtLogin()
        }
    }

    public var enablesHapticFeedback: Bool {
        didSet {
            UserDefaults.standard.set(enablesHapticFeedback, forKey: "looseleaf_enables_haptic_feedback")
        }
    }

    public var indexesFullContentInSpotlight: Bool {
        didSet {
            UserDefaults.standard.set(indexesFullContentInSpotlight, forKey: Self.spotlightFullContentKey)
            SpotlightIndexer.indexesFullContent = indexesFullContentInSpotlight
            if !indexesFullContentInSpotlight {
                SpotlightIndexer.clearIndex { [weak self] in
                    Task { @MainActor in
                        SpotlightIndexer.reindex(entries: self?.entries ?? [])
                    }
                }
            } else {
                SpotlightIndexer.reindex(entries: entries)
            }
        }
    }

    static let spotlightFullContentKey = "looseleaf_spotlight_full_content"

    public var notifiesOnSync: Bool {
        didSet {
            UserDefaults.standard.set(notifiesOnSync, forKey: "looseleaf_notifies_on_sync")
        }
    }

    @ObservationIgnored var hasBootstrapped: Bool = false
    @ObservationIgnored var inFlightPairTickets: Set<String> = []
    @ObservationIgnored var redeemedPairTickets: Set<String> = []
    public internal(set) var isConfirmingIncomingPairTicket: Bool = false

    public var hasOpenOverlay: Bool {
        activeConfirmDialog != nil
            || showSearchModal
            || showNewEntrySheet
            || lightboxAttachment != nil
            || editingEntry != nil
            || editingTransaction != nil
    }

    public internal(set) var pendingUploadCount: Int = 0
    public internal(set) var failedUploadCount: Int = 0
    public internal(set) var pendingEntriesCount: Int = 0
    public internal(set) var pendingTransactionsCount: Int = 0

    public var hubConnectionBadgeState: HubConnectionBadgeState {
        guard isPaired else { return .unpaired }
        guard isOnline else { return .offline }
        if failedUploadCount > 0 { return .syncFailed(count: failedUploadCount) }
        if isFlushingOutbox { return .syncing }
        if pendingUploadCount > 0 { return .pendingUpload(count: pendingUploadCount) }
        return .online
    }

    // MARK: - 派生数据记忆缓存与撤销栈存储（@ObservationIgnored 隔离非 UI 字段）
    @ObservationIgnored var entriesRevision: Int = 0
    @ObservationIgnored var transactionsRevision: Int = 0
    @ObservationIgnored var filteredMemo: (key: String, value: [LifeEntry])?
    @ObservationIgnored var streamRowsMemo: (key: String, value: [StreamRow])?
    @ObservationIgnored var entryCountsMemo: (key: String, value: [String: Int])?
    @ObservationIgnored var entriesByDateMemo: (key: String, value: [String: [LifeEntry]])?
    @ObservationIgnored var transactionIndexMemo: (Int, [Int: Transaction])?
    @ObservationIgnored var searchCorpusMemo: (Int, [SearchableLifeEntry])?
    @ObservationIgnored var onThisDayCacheDateKey: String?
    @ObservationIgnored var globalSearchGeneration: UInt64 = 0
    @ObservationIgnored var secondaryLoadGeneration: UInt64 = 0
    @ObservationIgnored var appliedEntriesFingerprint: SyncManager.CollectionFingerprint?
    @ObservationIgnored var appliedTransactionsFingerprint: SyncManager.CollectionFingerprint?

    var undoStack: [UndoAction] = []
    @ObservationIgnored var isUndoing = false

    private init() {
        let savedAppearance = UserDefaults.standard.string(forKey: "looseleaf_appearance_mode") ?? AppearanceMode.system.rawValue
        self.appearanceMode = AppearanceMode(rawValue: savedAppearance) ?? .system

        if let hubURL = Self.uiTestHubURL {
            APIClient.shared.setBaseURL(hubURL)
        }

        self.isPaired = (CredentialStore.getToken()?.isEmpty == false)
        self.accountName = CredentialStore.getAccountName() ?? ""
        self.accountEmail = CredentialStore.getAccountEmail() ?? ""
        self.showsDockIcon = UserDefaults.standard.object(forKey: "looseleaf_shows_dock_icon") as? Bool ?? true
        self.launchesAtLogin = UserDefaults.standard.object(forKey: "looseleaf_launches_at_login") as? Bool ?? false
        self.notifiesOnSync = UserDefaults.standard.object(forKey: "looseleaf_notifies_on_sync") as? Bool ?? true
        let spotlightFull = UserDefaults.standard.object(forKey: Self.spotlightFullContentKey) as? Bool ?? false
        self.indexesFullContentInSpotlight = spotlightFull
        SpotlightIndexer.indexesFullContent = spotlightFull
        self.enablesHapticFeedback = UserDefaults.standard.object(forKey: "looseleaf_enables_haptic_feedback") as? Bool ?? true

        self.isOnline = SyncManager.shared.isOnline
        self.isFlushingOutbox = SyncManager.shared.isFlushingOutbox

        SyncManager.shared.onSnapshotUpdated = { [weak self] snap in
            guard let self else { return }
            let nextOnline = SyncManager.shared.isOnline
            let nextFlushing = SyncManager.shared.isFlushingOutbox
            if self.isOnline != nextOnline { self.isOnline = nextOnline }
            if self.isFlushingOutbox != nextFlushing { self.isFlushingOutbox = nextFlushing }
            self.applySnapshot(snap)
        }

        SyncManager.shared.onLocalDataWarning = { [weak self] message in
            self?.localDataWarning = message
        }

        SyncManager.shared.onNetworkStatusChanged = { [weak self] online in
            guard let self, self.isOnline != online else { return }
            self.isOnline = online
        }

        SyncManager.shared.onOutboxFlushCompleted = { [weak self] attemptedCount in
            guard let self, self.notifiesOnSync else { return }
            let remaining = SyncManager.shared.currentSnapshot().outbox.count
            if remaining == 0, attemptedCount > 0 {
                AppDelegate.postNotification(
                    title: "活页集 · 同步完成",
                    body: "本地发件箱的 \(attemptedCount) 条记录已同步至中枢。"
                )
            } else if remaining > 0 {
                AppDelegate.postNotification(
                    title: "活页集 · 仍有待同步记录",
                    body: "有 \(remaining) 条本地记录暂未同步成功，将自动重试。"
                )
            }
        }

        applySnapshot(SyncManager.shared.currentSnapshot())
        Task { @MainActor [weak self] in
            self?.applyAppAppearance()
        }

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
                CredentialStore.clearAllCredentials()
                self.isPaired = false
                self.wipeAllLocalDeviceData()
                self.errorBanner = "登录状态已过期，本机缓存已自动清理，请通过 Vesper Auth 重新登录"
            }
        }
    }

    private func applySnapshot(_ snap: LocalArchiveSnapshot) {
        let entriesUseFingerprint = snap.entries.count >= SyncManager.fingerprintThreshold
        let transactionsUseFingerprint = snap.transactions.count >= SyncManager.fingerprintThreshold
        let snapshotFingerprint = (entriesUseFingerprint || transactionsUseFingerprint)
            ? SyncManager.shared.fingerprint(for: snap)
            : nil

        let entriesChanged: Bool
        if entriesUseFingerprint,
           let fingerprint = snapshotFingerprint?.entries,
           let previous = appliedEntriesFingerprint {
            entriesChanged = previous != fingerprint
        } else {
            entriesChanged = self.entries != snap.entries
        }

        let transactionsChanged: Bool
        if transactionsUseFingerprint,
           let fingerprint = snapshotFingerprint?.transactions,
           let previous = appliedTransactionsFingerprint {
            transactionsChanged = previous != fingerprint
        } else {
            transactionsChanged = self.transactions != snap.transactions
        }

        if entriesChanged { self.entries = snap.entries }
        if transactionsChanged { self.transactions = snap.transactions }
        if self.transactionSummary != snap.transactionSummary { self.transactionSummary = snap.transactionSummary }
        if self.profile != snap.profile { self.profile = snap.profile }
        if self.siteConfig != snap.siteConfig { self.siteConfig = snap.siteConfig }
        if self.stats != snap.stats { self.stats = snap.stats }
        if self.outboxItems != snap.outbox { self.outboxItems = snap.outbox }

        appliedEntriesFingerprint = entriesUseFingerprint ? snapshotFingerprint?.entries : nil
        appliedTransactionsFingerprint = transactionsUseFingerprint ? snapshotFingerprint?.transactions : nil
        if entriesChanged {
            SpotlightIndexer.reindex(entries: snap.entries)
        }
    }

    private func recomputeUploadCounts() {
        var pending = 0
        var failed = 0
        var entriesUnsynced = 0
        var txUnsynced = 0
        for entry in entries {
            let status = entry.syncStatus ?? "synced"
            if status != "synced" { entriesUnsynced += 1 }
            if status == "pending_create" { pending += 1 }
            else if status == "failed" { failed += 1 }
        }
        for tx in transactions {
            let status = tx.syncStatus ?? "synced"
            if status != "synced" { txUnsynced += 1 }
            if status == "pending_create" { pending += 1 }
            else if status == "failed" { failed += 1 }
        }
        if self.pendingUploadCount != pending { self.pendingUploadCount = pending }
        if self.failedUploadCount != failed { self.failedUploadCount = failed }
        if self.pendingEntriesCount != entriesUnsynced { self.pendingEntriesCount = entriesUnsynced }
        if self.pendingTransactionsCount != txUnsynced { self.pendingTransactionsCount = txUnsynced }
    }

    // MARK: - 远端全量与增量拉取

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await refreshAll()
        await UpdateChecker.shared.checkForUpdates(isUserInitiated: false)
    }

    public func refreshAll(forceFull: Bool = false) async {
        guard !isLoading else {
            showTemporaryBanner("正在同步档案，请稍候…")
            return
        }
        isLoading = true
        errorBanner = nil
        defer { isLoading = false }

        if forceFull {
            SyncManager.shared.resetPausedOutboxItems()
        }
        await SyncManager.shared.flushOutbox()

        SyncManager.shared.beginBatch()
        defer { SyncManager.shared.endBatch() }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadConfigAndProfile() }
            if self.isPaired {
                group.addTask { await self.loadEntries(forceFull: forceFull) }
                group.addTask { await self.loadCategories() }
                group.addTask { await self.loadWishes() }
                group.addTask { await self.loadTransactions(forceFull: forceFull) }
            }
        }
    }

    public func loadConfigAndProfile() async {
        async let cfg = try? APIClient.shared.fetchSiteConfig()
        async let prof = try? APIClient.shared.fetchCuratorProfile()
        async let st = try? APIClient.shared.fetchGlobalStats()
        let (siteConfig, profile, stats) = await (cfg, prof, st)
        SyncManager.shared.updateConfigAndProfile(siteConfig: siteConfig, profile: profile, stats: stats)
    }

    public func loadCategories() async {
        guard let list = try? await APIClient.shared.fetchCategories() else { return }
        self.expenseCategories = list.filter { $0.scope == "expense" }.map(\.name)
        self.incomeCategories = list.filter { $0.scope == "income" }.map(\.name)
        self.paymentMethods = list.filter { $0.scope == "payment" }.map(\.name)
    }

    private final class FirstPageGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
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
        let rawCursor = (forceFull || snap.entries.isEmpty) ? nil : snap.lastEntriesSyncCursor
        let cursor = SyncManager.lookbackCursor(rawCursor, seconds: 120)
        do {
            let firstPageGate = FirstPageGate()
            let allFetched = try await Pagination.fetchAllEntries(
                since: cursor,
                pageSize: 50,
                useETagOnFirstPage: !forceFull && cursor == nil
            ) { _, firstPage in
                guard firstPageGate.claim(), !firstPage.isEmpty else { return }
                await MainActor.run {
                    SyncManager.shared.mergeEntriesIncremental(firstPage)
                    SyncManager.shared.flushBatchSnapshotNow()
                }
            }
            await SyncManager.shared.mergeEntries(allFetched, isDelta: cursor != nil)
        } catch APIError.notModified {
            // 304 Not Modified
        } catch is CancellationError {
            // Cancelled
        } catch let APIError.serverError(_, message) where message.localizedCaseInsensitiveContains("since") || message.localizedCaseInsensitiveContains("时间格式") {
            Self.logger.warning("Invalid sync cursor detected: \(message, privacy: .public). Resetting cursors and falling back to full sync.")
            SyncManager.shared.resetSyncCursors()
            if !forceFull {
                await loadEntries(forceFull: true)
                return
            }
        } catch where error.localizedDescription.localizedCaseInsensitiveContains("since") || error.localizedDescription.localizedCaseInsensitiveContains("时间格式") {
            Self.logger.warning("Invalid sync cursor detected: \(error.localizedDescription, privacy: .public). Resetting cursors and falling back to full sync.")
            SyncManager.shared.resetSyncCursors()
            if !forceFull {
                await loadEntries(forceFull: true)
                return
            }
        } catch {
            self.errorBanner = error.localizedDescription
        }

        let todayKey = FormatUtils.beijingDateString()
        if onThisDayCacheDateKey != todayKey {
            if let otd = try? await APIClient.shared.fetchOnThisDayEntries() {
                self.onThisDayEntries = otd.entries
                onThisDayCacheDateKey = todayKey
            }
        }
    }

    public func loadTransactions(forceFull: Bool = false) async {
        guard isPaired else { return }
        let snap = SyncManager.shared.currentSnapshot()
        let rawCursor = (forceFull || snap.transactions.isEmpty) ? nil : snap.lastTransactionsSyncCursor
        let cursor = SyncManager.lookbackCursor(rawCursor, seconds: 120)

        do {
            let allTxs = try await Pagination.fetchAllTransactions(
                since: cursor,
                batchLimit: 500,
                useETagOnFirstBatch: !forceFull && cursor == nil
            )
            SyncManager.shared.mergeTransactions(allTxs, isDelta: cursor != nil)
        } catch APIError.notModified {
            // 304 Not Modified
        } catch let APIError.serverError(_, message) where message.localizedCaseInsensitiveContains("since") || message.localizedCaseInsensitiveContains("时间格式") {
            SyncManager.shared.resetSyncCursors()
            if !forceFull {
                await loadTransactions(forceFull: true)
                return
            }
        } catch where error.localizedDescription.localizedCaseInsensitiveContains("since") || error.localizedDescription.localizedCaseInsensitiveContains("时间格式") {
            SyncManager.shared.resetSyncCursors()
            if !forceFull {
                await loadTransactions(forceFull: true)
                return
            }
        } catch {
            // 保持本地缓存
        }

        let ym = FormatUtils.beijingCurrentYearMonth()
        async let channelsTask = try? APIClient.shared.fetchCreditChannels()
        for _ in 0..<2 {
            let before = SyncManager.shared.fingerprint(for: SyncManager.shared.currentSnapshot()).transactions
            guard let summary = try? await APIClient.shared.fetchTransactionSummary(year: ym.year, month: ym.month) else {
                break
            }
            let after = SyncManager.shared.fingerprint(for: SyncManager.shared.currentSnapshot()).transactions
            if before == after {
                SyncManager.shared.updateTransactionSummary(summary)
                break
            }
        }
        if let channels = await channelsTask {
            self.creditChannels = channels
        }
    }

    public func refreshAfterSecondaryWrite() async {
        await loadWishes()
        await loadEntries(forceFull: false)
    }

    public func loadWishes() async {
        secondaryLoadGeneration &+= 1
        let gen = secondaryLoadGeneration

        let allWishes = try? await Pagination.fetchAllWishes()

        guard gen == secondaryLoadGeneration else { return }

        if let allWishes {
            self.wishes = allWishes
        }
    }

    // MARK: - Dock 图标策略、登录启动与瞬时横幅

    private func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = showsDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

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
