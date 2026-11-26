import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 独立观察 `AppBanners` 的顶部提示浮层：
/// 避免弹吐司/关闭报错时触发整棵 `StreamView` 与几百张卡片的 diff 重算。
private struct StreamBannerOverlay: View {
    @Bindable var banners: AppBanners

    var body: some View {
        VStack(spacing: 4) {
            if let err = banners.error {
                noticeStrip(text: err, isError: true) {
                    banners.error = nil
                }
            }
            if let warning = banners.localWarning {
                noticeStrip(text: warning, isError: true) {
                    banners.localWarning = nil
                }
            }
            if let status = banners.status {
                noticeStrip(text: status, isError: false) {
                    banners.status = nil
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .allowsHitTesting(true)
    }

    private func noticeStrip(text: String, isError: Bool, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(isError ? ArchivePalette.accentWarm : ArchivePalette.accentMoss)
            Text(text)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Spacer()
            Button("关闭") {
                onDismiss()
            }
            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
            .buttonStyle(.plain)
            .paperButtonFocusRing(cornerRadius: 3)
            .foregroundStyle(ArchivePalette.inkMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
    }
}

/// 桌面主窗口工作台与时间流视图 (StreamView)
/// 严格遵循 macOS HIG 规范：
/// 1. 升级为原生 `NavigationSplitView`（支持 `⌃⌘S` 侧栏折叠、拖拽调宽与 13"/14" 分屏自适应）
/// 2. 主内容区采用纯纸色基底（`enableVibrancy: false`），消除 5K 大屏离屏高斯模糊过度绘制
/// 3. 搜索输入 120ms 防抖、横幅独立订阅隔离、渐进式 150 条视口窗口化与主窗口关闭缓存回收
@MainActor
public struct StreamView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var splitContainerWidth: CGFloat = 1180
    @State private var keyboardScrollPosition: Int?
    @State private var localSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var visibleRowLimit: Int = 150

    @State private var timelineActions = TimelineEntryActions()

    public init(appState: AppState) {
        self.appState = appState
    }

    private var currentWindowTitle: String {
        switch appState.activeSection {
        case .ledger:
            return appState.navigation.ledgerSubTab == .ledger ? "记账 · 流水" : "记账 · 心愿单"
        case .stream, .preferences, .hub, .about:
            let rawName = appState.siteConfig.siteName.split(separator: "·").first?.trimmingCharacters(in: .whitespaces) ?? "散页"
            return rawName.isEmpty ? "散页" : rawName
        }
    }

    private var currentWindowSubtitle: String {
        switch appState.activeSection {
        case .ledger:
            return appState.navigation.ledgerSubTab == .ledger
                ? "日常收支流水与月度类目光谱"
                : "好物 · 旅程 · 里程碑"
        case .stream, .preferences, .hub, .about:
            return [appState.profile.displayCity, FormatUtils.beijingDateString()]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
    }

    private var currentSearchPrompt: String {
        switch appState.activeSection {
        case .ledger:
            return appState.navigation.ledgerSubTab == .ledger ? "筛选账目流水…" : "筛选心愿清单…"
        case .stream, .preferences, .hub, .about:
            return "搜索散页手记…"
        }
    }

    private var inspectorPresentedBinding: Binding<Bool> {
        Binding(
            get: { appState.activeSection == .stream && appState.highlightedEntry != nil },
            set: { presented in
                if !presented {
                    appState.highlightedEntry = nil
                }
            }
        )
    }

    private func toggleInspector() {
        guard appState.activeSection == .stream else { return }
        if appState.highlightedEntry != nil {
            appState.highlightedEntry = nil
        } else if let focusedId = appState.keyboardFocusedEntryId,
                  let found = appState.filteredStreamEntries.first(where: { $0.id == focusedId })
                    ?? appState.entries.first(where: { $0.id == focusedId }) {
            appState.highlightedEntry = found
        } else if let first = appState.filteredStreamEntries.first {
            appState.keyboardFocusedEntryId = first.id
            appState.highlightedEntry = first
        }
    }

    public var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                workbenchSidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 270)
            } detail: {
                ZStack {
                    NoiseBackground(useSubtleSurface: false, enableVibrancy: false)

                    Group {
                        switch appState.activeSection {
                        case .ledger:
                            sectionContentView(for: .ledger)
                                .modifier(WorkbenchCanvasMaxWidth(maxWidth: 1120))
                                .transition(.opacity)
                        case .stream, .preferences, .hub, .about:
                            sectionContentView(for: .stream)
                                .modifier(WorkbenchCanvasMaxWidth(maxWidth: 960))
                                .transition(.opacity)
                        }
                    }
                    .id(appState.activeSection == .ledger ? WorkbenchSection.ledger : WorkbenchSection.stream)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: appState.activeSection)
                    .overlay(alignment: .top) {
                        StreamBannerOverlay(banners: appState.banners)
                    }
                }
                .navigationTitle(currentWindowTitle)
                .navigationSubtitle(currentWindowSubtitle)
            }
            .inspector(isPresented: inspectorPresentedBinding) {
                Group {
                    if let entry = appState.highlightedEntry {
                        StreamEntryDetailView(
                            entry: entry,
                            appState: appState,
                            presentationStyle: .inspector,
                            onClose: { appState.highlightedEntry = nil },
                            onOpenInNewWindow: { appState.detailWindowEntry = $0 },
                            onEditEntry: { appState.editingEntry = $0 },
                            onEditTransaction: { appState.editingTransaction = $0 },
                            onDeleteTransaction: { appState.deleteTransactionAction($0) }
                        )
                    }
                }
                .inspectorColumnWidth(min: 300, ideal: 360, max: 520)
            }
            .toolbar {
                if appState.activeSection == .stream {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            toggleInspector()
                        } label: {
                            Label("检视散页详情", systemImage: "sidebar.trailing")
                        }
                        .help("切换右侧散页检视器 (⌥⌘I)")
                        .keyboardShortcut("i", modifiers: [.command, .option])
                        .disabled(!appState.isPaired || appState.hasOpenOverlay)
                    }
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            splitContainerWidth = proxy.size.width
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            splitContainerWidth = newWidth
                            if inspectorPresentedBinding.wrappedValue, newWidth < 1040, columnVisibility != .detailOnly {
                                columnVisibility = .detailOnly
                            }
                        }
                }
            )
            .onChange(of: appState.highlightedEntry?.id) { _, newId in
                if newId != nil, appState.activeSection == .stream, splitContainerWidth < 1040, columnVisibility != .detailOnly {
                    columnVisibility = .detailOnly
                }
            }
            .onChange(of: appState.entries) { _, newEntries in
                guard let current = appState.highlightedEntry, current.type != "transaction" else { return }
                if let updated = newEntries.first(where: { $0.id == current.id }) {
                    if updated != current {
                        appState.highlightedEntry = updated
                    }
                } else if current.id > 0 {
                    appState.highlightedEntry = nil
                }
            }
            .searchable(text: $localSearchText, placement: .toolbar, prompt: currentSearchPrompt)
            .accessibilityHidden(appState.hasOpenOverlay)

            // 暗房全屏看图灯箱
            if let att = appState.lightboxAttachment {
                EditorialLightboxView(
                    attachment: att,
                    allAttachments: appState.entries.first(where: { $0.attachments.contains(where: { $0.id == att.id }) })?.attachments ?? [att]
                ) {
                    appState.lightboxAttachment = nil
                }
            }

            // 全局聚光灯档案检索 (⌘K Spotlight) —— 命中散页或心愿后精准跳转
            if appState.showSearchModal {
                PaperModalOverlay(onDismiss: {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        appState.showSearchModal = false
                    }
                }) {
                    GlobalSearchModalView(
                        appState: appState,
                        onDismiss: {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                                appState.showSearchModal = false
                            }
                        },
                        onSelectEntry: { entry in
                            appState.highlightedEntry = entry
                        },
                        onSelectWish: { wish in
                            appState.navigation.highlightedWishId = wish.id
                            appState.navigation.ledgerSubTab = .wishlist
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                                appState.activeSection = .ledger
                            }
                        }
                    )
                }
                .zIndex(120)
            }
        }
        .background(
            HostingWindowCloseObserver {
                // 主窗口关闭退驻后台/菜单栏时主动释放 ~120MB 位图解码缓存池
                PaperImageCache.clearMemoryCache()
            }
        )
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        .sheet(isPresented: $appState.showNewEntrySheet) {
            NewEntryModal(appState: appState) {
                appState.showNewEntrySheet = false
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .sheet(item: $appState.editingEntry) { entry in
            editEntrySheet(entry: entry)
                .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .sheet(item: $appState.editingTransaction) { tx in
            EditTransactionSheet(appState: appState, transaction: tx) {
                appState.editingTransaction = nil
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .alert(
            appState.activeConfirmDialog?.title ?? "请确认",
            isPresented: Binding(
                get: { appState.activeConfirmDialog != nil },
                set: { if !$0 { appState.activeConfirmDialog = nil } }
            ),
            presenting: appState.activeConfirmDialog
        ) { req in
            Button(req.confirmText, role: req.danger ? .destructive : nil) {
                if appState.enablesHapticFeedback { ArchiveFeedback.light() }
                let action = req.onConfirm
                appState.activeConfirmDialog = nil
                action()
            }
            Button(req.cancelText, role: .cancel) {
                appState.dismissConfirm()
            }
        } message: { req in
            Text(req.message)
        }
        .onAppear {
            localSearchText = appState.searchQuery
        }
        .onChange(of: localSearchText) { _, newVal in
            searchDebounceTask?.cancel()
            if newVal.isEmpty {
                appState.searchQuery = ""
                visibleRowLimit = 150
            } else {
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled else { return }
                    appState.searchQuery = newVal
                    visibleRowLimit = 150
                }
            }
        }
        .onChange(of: appState.searchQuery) { _, newVal in
            if localSearchText != newVal {
                localSearchText = newVal
            }
        }
        .onChange(of: appState.searchFocusRequest) { _, _ in
            ToolbarSearchFocus.activate()
        }
        .onChange(of: appState.detailWindowEntry?.id) { _, newValue in
            guard let id = newValue else { return }
            openWindow(id: "detail", value: id)
        }
        .onChange(of: appState.activeSection) { _, newSec in
            // 若旧路径误把 activeSection 切到配置枚举，自动重定向打开独立 Settings 窗口并保持当前内容板块
            if WorkbenchSection.configurationSections.contains(newSec) {
                let tab: SettingsTab = switch newSec {
                case .hub: .devices
                case .about: .about
                default: .general
                }
                appState.activeSection = .stream
                appState.navigation.settingsSelectedTab = tab
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        .onChange(of: appState.navigation.settingsOpenToken) { _, _ in
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .onExitCommand {
            if appState.showSearchModal {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { appState.showSearchModal = false }
            } else if appState.lightboxAttachment != nil {
                appState.lightboxAttachment = nil
            }
        }
    }

    // MARK: - 主画布内容分发

    @ViewBuilder
    private func sectionContentView(for section: WorkbenchSection) -> some View {
        switch section {
        case .stream:
            streamTimelineCanvas
        case .ledger:
            LedgerAssetsView(appState: appState)
        case .preferences, .hub, .about:
            streamTimelineCanvas
        }
    }

    private var workbenchSidebar: some View {
        WorkbenchSidebar(
            appState: appState,
            onSelect: { section in
                guard appState.activeSection != section else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                    appState.activeSection = section
                }
            }
        )
    }

    // MARK: - 右侧时间流主画布

    private var streamTimelineCanvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. 刊头诗意排版（窗口标题与日期已上移至原生标题栏）
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            let rawName = appState.siteConfig.siteName.split(separator: "·").first?.trimmingCharacters(in: .whitespaces) ?? "散页"
                            Text(rawName.isEmpty ? "散页" : rawName)
                                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.display, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)

                            let sub = appState.siteConfig.siteSubtitle ?? ""
                            let subtitle = sub.isEmpty ? "日常 · 流水 · 心愿" : sub
                            Text(subtitle)
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        // 私密条目快捷筛选胶囊
                        let privateOnly = appState.navigation.streamPrivacyFilter == .privateOnly
                        PaperPillButton(
                            title: "私密",
                            icon: "lock.fill",
                            isSelected: privateOnly
                        ) {
                            appState.navigation.streamPrivacyFilter = privateOnly ? .all : .privateOnly
                            visibleRowLimit = 150
                        }
                    }

                    if !appState.profile.motto.isEmpty {
                        Text("“\(appState.profile.motto)”")
                            .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .italic()
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(ArchiveCategory.primaryCases) { cat in
                                    if cat != .transaction || appState.isPaired {
                                        PaperPillButton(
                                            title: cat.label,
                                            isSelected: appState.selectedCategory == cat,
                                            isCompact: true
                                        ) {
                                            guard appState.selectedCategory != cat else { return }
                                            appState.selectedCategory = cat
                                            visibleRowLimit = 150
                                        }
                                    }
                                }

                                Rectangle()
                                    .fill(ArchivePalette.borderDivider)
                                    .frame(width: 1, height: 14)
                                    .padding(.horizontal, 4)
                                    .accessibilityHidden(true)

                                ForEach(ArchiveCategory.galleryCases) { cat in
                                    let entryCat = cat.entryCategory
                                    PaperPillButton(
                                        title: cat.label,
                                        icon: differentiateWithoutColor ? entryCat?.symbolName : nil,
                                        leadingDotColor: differentiateWithoutColor ? nil : entryCat?.accentColor,
                                        accentColor: entryCat?.accentColor,
                                        isSelected: appState.selectedCategory == cat,
                                        isCompact: true
                                    ) {
                                        guard appState.selectedCategory != cat else { return }
                                        appState.selectedCategory = cat
                                        visibleRowLimit = 150
                                    }
                                }
                            }
                    }
                }
                .padding(.bottom, 6)

                Divider().overlay(ArchivePalette.borderSubtle)

                // 2. 那年今日 · 岁月回响旧信笺
                if !appState.onThisDayEntries.isEmpty {
                    onThisDayBannerCard
                }

                // 3. 编年时间流（渐进式视口窗口化：默认挂载前 150 条，触底哨兵平滑扩容）
                let allRows = appState.streamRows
                if allRows.isEmpty {
                    if appState.isLoading {
                        ArchiveSkeletonView(rowCount: 4)
                    } else {
                        emptyStreamPlaceholder
                    }
                } else {
                    let effectiveLimit = effectiveVisibleRowLimit(for: allRows)
                    let displayedRows = allRows.prefix(effectiveLimit)
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(displayedRows) { row in
                            let entry = row.entry
                            if row.gapDays >= 14 {
                                TemporalGapDivider(days: row.gapDays)
                            }
                            TimelineEntryCardView(
                                entry: entry,
                                timeLabel: row.timeLabel,
                                transaction: matchingTransaction(for: entry),
                                isSelected: appState.highlightedEntry?.id == entry.id,
                                isKeyboardFocused: appState.keyboardFocusedEntryId == entry.id,
                                actions: timelineActions
                            )
                            .id(entry.id)
                        }

                        if allRows.count > effectiveLimit {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在展开更多历史印记（已载入 \(effectiveLimit) / \(allRows.count)）…")
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .onAppear {
                                visibleRowLimit = min(allRows.count, visibleRowLimit + 150)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
        .scrollPosition(id: $keyboardScrollPosition)
        .onAppear {
            if keyboardScrollPosition == nil, let saved = appState.navigation.streamScrollEntryId {
                keyboardScrollPosition = saved
            }
        }
        .onChange(of: keyboardScrollPosition) { _, newValue in
            if appState.activeSection == .stream, let newValue {
                appState.navigation.streamScrollEntryId = newValue
            }
        }
        .onChange(of: appState.keyboardFocusedEntryId) { _, newValue in
            guard let id = newValue else { return }
            let allRows = appState.streamRows
            if let idx = allRows.firstIndex(where: { $0.id == id }), idx >= visibleRowLimit {
                visibleRowLimit = min(allRows.count, idx + 50)
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                keyboardScrollPosition = id
            }
        }
    }

    private func effectiveVisibleRowLimit(for rows: [AppState.StreamRow]) -> Int {
        min(rows.count, max(150, visibleRowLimit))
    }

    private func matchingTransaction(for entry: LifeEntry) -> Transaction? {
        if let associated = entry.associatedTransactionId {
            return appState.transactionById[Int(associated)]
        }
        if entry.type == "transaction" {
            return appState.transactionById[entry.id]
        }
        return nil
    }

    // MARK: - 空态与那年今日

    private var emptyStreamPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: appState.navigation.streamPrivacyFilter == .privateOnly ? "lock.doc" : "book.closed")
                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.emptyIcon, weight: .light))
                .foregroundStyle(ArchivePalette.inkMuted)
            Text(appState.navigation.streamPrivacyFilter == .privateOnly ? "暂无仅自己可见的私密散页" : "散页手记尚待落墨")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .medium))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Text(appState.navigation.streamPrivacyFilter == .privateOnly ? "在记一笔或右键卡片菜单中可将内容标记为仅自己可见" : "记录真实可感的当下")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.mediumBody))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    private var onThisDayBannerCard: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Text("岁月回响")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro, weight: .bold))
                            .foregroundStyle(ArchivePalette.archivePaper)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ArchivePalette.accentWarm)
                            .clipShape(RoundedRectangle(cornerRadius: 2))

                        Text("那年今日 · ON THIS DAY")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.footnote, weight: .semibold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }

                    Spacer()

                    Text("往年今日 \(appState.onThisDayEntries.count) 篇在册印记")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.label))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Divider().overlay(ArchivePalette.accentWarm.opacity(0.3))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(appState.onThisDayEntries.prefix(4)) { entry in
                        let firstContentLine = entry.content
                            .split(whereSeparator: \.isNewline)
                            .first
                            .map(String.init)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let mainText = entry.hasDistinctTitle ? entry.title : (firstContentLine.isEmpty ? "无题散页" : firstContentLine)
                        Button {
                            appState.highlightedEntry = entry
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        if entry.isPrivate {
                                            Image(systemName: "lock.fill")
                                                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.miniBadge))
                                                .foregroundStyle(ArchivePalette.accentWarm)
                                        }
                                        Text(mainText)
                                            .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                            .lineLimit(1)
                                    }

                                    if entry.hasDistinctTitle && !entry.content.isEmpty {
                                        Text(entry.content)
                                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(entry.parsedDate.dotDate)
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.label))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .paperHover()
                        .paperButtonFocusRing()
                        .accessibilityLabel("那年今日：\(entry.isPrivate ? "私密，" : "")\(mainText)，\(entry.parsedDate.dotDate)")
                    }
                }
            }
            .padding(14)
            .background(ArchivePalette.accentWarm.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ArchivePalette.accentWarm.opacity(0.35), lineWidth: 0.8)
            )

            VStack {
                HStack {
                    Text("⌜").font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption)).foregroundStyle(ArchivePalette.accentWarm.opacity(0.6))
                    Spacer()
                    Text("⌝").font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption)).foregroundStyle(ArchivePalette.accentWarm.opacity(0.6))
                }
                Spacer()
                HStack {
                    Text("⌞").font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption)).foregroundStyle(ArchivePalette.accentWarm.opacity(0.6))
                    Spacer()
                    Text("⌟").font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption)).foregroundStyle(ArchivePalette.accentWarm.opacity(0.6))
                }
            }
            .padding(4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func editEntrySheet(entry: LifeEntry) -> some View {
        EditEntrySheetView(entry: entry) { updated in
            _ = try await APIClient.shared.updateEntry(id: entry.id, updated)
            await appState.loadEntries(forceFull: false)
            await appState.loadConfigAndProfile()
            appState.editingEntry = nil
        } onCancel: {
            appState.editingEntry = nil
        }
    }
}
