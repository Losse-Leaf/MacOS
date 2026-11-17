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
                .font(ArchiveTypography.bodySans(size: 12))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Spacer()
            Button("关闭") {
                onDismiss()
            }
            .font(ArchiveTypography.bodySans(size: 11))
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

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var keyboardScrollPosition: Int?
    @State private var localSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var visibleRowLimit: Int = 150
    @FocusState private var isSearchFocused: Bool

    @State private var visitedSections: Set<WorkbenchSection> = [.stream]
    @State private var timelineActions = TimelineEntryActions()

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                workbenchSidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 270)
            } detail: {
                ZStack {
                    NoiseBackground(useSubtleSurface: false, enableVibrancy: false)

                    ZStack {
                        if visitedSections.contains(.stream) {
                            sectionContentView(for: .stream)
                                .modifier(WorkbenchCanvasMaxWidth(maxWidth: 960))
                                .opacity(appState.activeSection == .stream ? 1 : 0)
                                .allowsHitTesting(appState.activeSection == .stream)
                                .zIndex(appState.activeSection == .stream ? 1 : 0)
                        }

                        if appState.activeSection != .stream {
                            let section = appState.activeSection
                            sectionContentView(for: section)
                                .modifier(WorkbenchCanvasMaxWidth(maxWidth: 1120))
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: appState.activeSection)
                    .overlay(alignment: .top) {
                        StreamBannerOverlay(banners: appState.banners)
                    }
                }
            }
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

            if appState.showNewEntrySheet {
                PaperModalOverlay(onDismiss: {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        appState.showNewEntrySheet = false
                    }
                }) {
                    NewEntryModal(
                        appState: appState,
                        initialKind: appState.newEntryInitialKind,
                        initialProjectId: appState.newEntryInitialProjectId,
                        initialCityCode: appState.newEntryInitialCityCode,
                        initialCityName: appState.newEntryInitialCityName
                    ) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                            appState.showNewEntrySheet = false
                            appState.newEntryInitialKind = nil
                            appState.newEntryInitialProjectId = nil
                            appState.newEntryInitialCityCode = nil
                            appState.newEntryInitialCityName = nil
                        }
                    }
                }
                .zIndex(110)
            }

            // 全局聚光灯档案检索 (⌘K Spotlight) —— 命中二级实体后精准跳转并高亮/开抽屉
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
                        onSelectFootprint: { fp in
                            appState.navigation.highlightedFootprintCity = CityJumpTarget(
                                code: fp.cityCode,
                                name: fp.cityName
                            )
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                                appState.activeSection = .atlas
                            }
                        },
                        onSelectWish: { wish in
                            appState.navigation.highlightedWishId = wish.id
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                                appState.activeSection = .wishes
                            }
                        },
                        onSelectProject: { proj in
                            appState.navigation.highlightedProjectId = proj.id
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                                appState.activeSection = .projects
                            }
                        }
                    )
                }
                .zIndex(120)
            }

            // 全局统一纸本确认 / 警示弹窗
            if let req = appState.activeConfirmDialog {
                PaperConfirmDialogView(request: req) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        appState.activeConfirmDialog = nil
                    }
                }
                .zIndex(130)
            }
        }
        .background(
            HostingWindowCloseObserver {
                // 主窗口关闭退驻后台/菜单栏时主动释放 ~120MB 位图解码缓存池
                PaperImageCache.clearMemoryCache()
            }
        )
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        .sheet(item: $appState.editingEntry) { entry in
            editEntrySheet(entry: entry)
                .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .sheet(item: $appState.editingTransaction) { tx in
            EditTransactionSheet(appState: appState, transaction: tx) {
                appState.editingTransaction = nil
                Task { @MainActor in
                    await appState.loadTransactionsAndAssets(forceFull: false)
                    await appState.loadEntries(forceFull: false)
                }
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .sheet(item: $appState.highlightedEntry) { entry in
            entryDetailSheet(entry: entry)
                .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .onAppear {
            localSearchText = appState.searchQuery
            visitedSections.insert(appState.activeSection)
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
            visitedSections.insert(newSec)
        }
        .onChange(of: appState.navigation.settingsOpenToken) { _, _ in
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .onExitCommand {
            if appState.activeConfirmDialog != nil {
                appState.dismissConfirm()
            } else if appState.showSearchModal {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { appState.showSearchModal = false }
            } else if appState.showNewEntrySheet {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { appState.showNewEntrySheet = false }
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
        case .wishes:
            WishlistView(appState: appState)
        case .atlas:
            TravelAtlasView(appState: appState)
        case .projects:
            ProjectsView(appState: appState)
        case .dossier:
            CuratorDossierView(appState: appState)
        case .preferences, .hub, .about:
            streamTimelineCanvas
        }
    }

    private var workbenchSidebar: some View {
        WorkbenchSidebar(
            appState: appState,
            onSelect: { section in
                guard appState.activeSection != section else { return }
                visitedSections.insert(section)
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
                // 1. 刊头诗意排版
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            let rawName = appState.siteConfig.siteName.split(separator: "·").first?.trimmingCharacters(in: .whitespaces) ?? "散页"
                            Text(rawName.isEmpty ? "散页" : rawName)
                                .font(ArchiveTypography.editorialSerif(size: 26, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)

                            let sub = appState.siteConfig.siteSubtitle ?? ""
                            let subtitle = sub.isEmpty ? "日常 · 资产 · 心愿 · 行迹 · 造物" : sub
                            Text(subtitle)
                                .font(ArchiveTypography.monoScale(size: 12))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .lineLimit(1)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            if !appState.profile.displayCity.isEmpty {
                                Text("\(appState.profile.displayCity) ·")
                            }
                            Text(FormatUtils.beijingDateString())
                        }
                        .font(ArchiveTypography.monoScale(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .lineLimit(1)
                    }

                    if !appState.profile.motto.isEmpty {
                        Text("“\(appState.profile.motto)”")
                            .font(ArchiveTypography.editorialSerif(size: 13))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .italic()
                            .padding(.top, 1)
                    }

                    // 检索与分类胶囊工具条（窄窗/分屏下分类胶囊自动横向滚动，绝不挤压搜索框）
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(isSearchFocused ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                            TextField("即时搜索散页与票根… (⌘F)", text: $localSearchText)
                                .accessibilityLabel("搜索散页与票根")
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.bodySans(size: 12))
                                .focused($isSearchFocused)
                                .frame(maxWidth: .infinity)
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
                            if !localSearchText.isEmpty {
                                Button {
                                    searchDebounceTask?.cancel()
                                    localSearchText = ""
                                    appState.searchQuery = ""
                                    visibleRowLimit = 150
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                        .frame(minWidth: 24, minHeight: 24)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("清空搜索关键词")
                                .buttonStyle(.plain)
                                .paperButtonFocusRing(cornerRadius: 4)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 260)
                        .frame(height: 32)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                                .stroke(isSearchFocused ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle.opacity(0.6), lineWidth: isSearchFocused ? 1.0 : 0.5)
                        )
                        .paperElevation(1)

                        Spacer(minLength: 8)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(ArchiveCategory.allCases) { cat in
                                    if cat != .transaction || appState.isPaired {
                                        PaperPillButton(
                                            title: cat.label,
                                            isSelected: appState.selectedCategory == cat
                                        ) {
                                            guard appState.selectedCategory != cat else { return }
                                            appState.selectedCategory = cat
                                            visibleRowLimit = 150
                                        }
                                    }
                                }

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
                                    .font(ArchiveTypography.monoScale(size: 11))
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
        .onChange(of: appState.searchFocusRequest) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                isSearchFocused = true
            }
        }
        .onChange(of: appState.detailWindowEntry?.id) { _, newValue in
            guard let id = newValue else { return }
            openWindow(id: "detail", value: id)
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
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ArchivePalette.inkMuted)
            Text(appState.navigation.streamPrivacyFilter == .privateOnly ? "暂无仅自己可见的私密散页" : "散页手记尚待落墨")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .medium))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Text(appState.navigation.streamPrivacyFilter == .privateOnly ? "在记一笔或右键卡片菜单中可将内容标记为仅自己可见" : "记录真实可感的当下")
                .font(ArchiveTypography.bodySans(size: 12.5))
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
                            .font(ArchiveTypography.monoScale(size: 10, weight: .bold))
                            .foregroundStyle(ArchivePalette.archivePaper)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ArchivePalette.accentWarm)
                            .clipShape(RoundedRectangle(cornerRadius: 2))

                        Text("那年今日 · ON THIS DAY")
                            .font(ArchiveTypography.monoScale(size: 11.5, weight: .semibold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }

                    Spacer()

                    Text("往年今日 \(appState.onThisDayEntries.count) 篇在册印记")
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Divider().overlay(ArchivePalette.accentWarm.opacity(0.3))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(appState.onThisDayEntries.prefix(4)) { entry in
                        let mainText = entry.title.isEmpty ? (entry.content.isEmpty ? "无题散页" : entry.content) : entry.title
                        Button {
                            appState.highlightedEntry = entry
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        if entry.isPrivate {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(ArchivePalette.accentWarm)
                                        }
                                        Text(mainText)
                                            .font(ArchiveTypography.editorialSerif(size: 13, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                            .lineLimit(1)
                                    }

                                    if !entry.title.isEmpty && !entry.content.isEmpty {
                                        Text(entry.content)
                                            .font(ArchiveTypography.bodySans(size: 11))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(entry.parsedDate.dotDate)
                                    .font(ArchiveTypography.monoScale(size: 10.5))
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
                    Text("⌜").font(ArchiveTypography.monoScale(size: 11)).foregroundStyle(ArchivePalette.accentWarm.opacity(0.6))
                    Spacer()
                    Text("⌝").font(ArchiveTypography.monoScale(size: 11)).foregroundStyle(ArchivePalette.accentWarm.opacity(0.6))
                }
                Spacer()
                HStack {
                    Text("⌞").font(ArchiveTypography.monoScale(size: 11)).foregroundStyle(ArchivePalette.accentWarm.opacity(0.6))
                    Spacer()
                    Text("⌟").font(ArchiveTypography.monoScale(size: 11)).foregroundStyle(ArchivePalette.accentWarm.opacity(0.6))
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

    private func entryDetailSheet(entry: LifeEntry) -> some View {
        StreamEntryDetailView(
            entry: entry,
            appState: appState,
            isStandaloneWindow: false,
            onEditEntry: { appState.editingEntry = $0 },
            onEditTransaction: { appState.editingTransaction = $0 },
            onDeleteTransaction: { appState.deleteTransactionAction($0) }
        )
        .frame(width: 560)
        .background(ArchivePalette.archivePaper)
    }
}
