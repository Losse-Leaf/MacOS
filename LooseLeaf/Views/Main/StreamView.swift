import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 桌面主窗口工作台与时间流视图 (StreamView)
/// 严格遵循 docs/macos.md §6 & §7 与 docs/web.md §2.5 规范：
/// 1. 叠加纸张微噪点与系统 Vibrancy 半透明材质
/// 2. 集成 52 周生活刻度热力图、四维分类过滤、#标签下钻与即时模糊搜索
/// 3. 相邻记录跨度 >= 14 天自动渲染「岁月留白刻度切线」
/// 4. 胶片相纸以 .film-frame 装裱呈现，点击进入暗房大图灯箱
@MainActor
public struct StreamView: View {
    @Bindable var appState: AppState
    /// 打开独立详情窗口（深链 / 「在新窗口打开」）
    @Environment(\.openWindow) private var openWindow

    // 键盘流与检索状态
    @State private var keyboardScrollPosition: Int?
    /// 系统配置分组折叠状态（持久化，避免每次启动都要重新展开 12 项）
    @State private var isSystemGroupCollapsed: Bool = UserDefaults.standard.bool(forKey: "looseleaf_ui_system_group_collapsed")
    @State private var localSearchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var isOnThisDayExpanded: Bool = true

    public enum StreamTimelineDisplayMode: String, CaseIterable, Identifiable {
        case treeTimeline = "树状时间轴"
        case treeDiagram = "事件树谱全景"

        public var id: String { rawValue }
    }
    @State private var streamTimelineMode: StreamTimelineDisplayMode = .treeTimeline

    // 管理模式：编辑与删除状态
    // 编辑态放在 AppState（见 AppState.editingEntry 的说明）：
    // 行为闭包只捕获 AppState 单例 → 整轮时间流共享同一份 actions 引用
    // → SwiftUI 能跳过内容没变的卡片。
    // 全局检索关联发现弹窗
    @State private var inspectingSearchFootprint: Footprint?
    @State private var inspectingSearchWish: Wish?
    @State private var inspectingSearchProject: Project?

    @State private var visitedSections: Set<WorkbenchSection> = [.stream]

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack {
            NoiseBackground(useSubtleSurface: false, enableVibrancy: true)

            HStack(spacing: 0) {
                // 左侧出版物目录侧栏
                workbenchSidebar
                    .frame(width: 225)

                Rectangle()
                    .fill(ArchivePalette.borderDivider)
                    .frame(width: 0.5)

                // 右侧主画布区
                VStack(spacing: 0) {
                    ZStack {
                        // 仅时间流常驻（保留滚动位置与键盘流焦点）；其余板块按需挂载，
                        // 避免 12 个板块同时存活导致任意 AppState 变更触发全量隐藏视图重算
                        if visitedSections.contains(.stream) {
                            sectionContentView(for: .stream)
                                .modifier(WorkbenchCanvasMaxWidth(maxWidth: 960))
                                .padding(.bottom, 48)
                                .opacity(appState.activeSection == .stream ? 1 : 0)
                                .allowsHitTesting(appState.activeSection == .stream)
                                .zIndex(appState.activeSection == .stream ? 1 : 0)
                        }

                        if appState.activeSection != .stream {
                            let section = appState.activeSection
                            sectionContentView(for: section)
                                .modifier(WorkbenchCanvasMaxWidth(maxWidth: 1120))
                                .padding(.bottom, WorkbenchSection.configurationSections.contains(section) ? 0 : 48)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .archiveAnimation(.easeInOut(duration: 0.12), value: appState.activeSection)
                    // 通知条改为浮层：不参与主画布布局，出现/消失不再导致内容跳动；
                    // 且三类提示可叠加（原先互斥，错误会被信息条遮住）。
                    .overlay(alignment: .top) {
                        VStack(spacing: 4) {
                            if let err = appState.errorBanner {
                                topNoticeStrip(text: err, isError: true) {
                                    appState.errorBanner = nil
                                }
                            }
                            if let warning = appState.localDataWarning {
                                topNoticeStrip(text: warning, isError: true) {
                                    appState.localDataWarning = nil
                                }
                            }
                            if let banner = appState.statusBanner {
                                topNoticeStrip(text: banner, isError: false) {
                                    appState.statusBanner = nil
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .allowsHitTesting(true)
                    }

                }
            }

            // 暗房全屏看图灯箱
            if let att = appState.lightboxAttachment {
                EditorialLightboxView(
                    attachment: att,
                    allAttachments: appState.entries.first(where: { $0.attachments.contains(where: { $0.id == att.id }) })?.attachments ?? [att]
                ) {
                    appState.lightboxAttachment = nil
                }
            }

            // 说明：原先此处有一个右下角悬浮「+」按钮（FAB）。
            // FAB 是移动端范式，在 macOS 上会随窗口尺寸漂移并遮挡右下角内容，
            // 现已改为窗口右上角的原生工具栏按钮（⌘N 快捷键保持不变）。

            if appState.showNewEntrySheet {
                PaperModalOverlay(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.16)) {
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
                        withAnimation(.easeInOut(duration: 0.16)) {
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

            // 全局聚光灯档案检索 (⌘K Spotlight)
            if appState.showSearchModal {
                PaperModalOverlay(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        appState.showSearchModal = false
                    }
                }) {
                    GlobalSearchModalView(
                        appState: appState,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.showSearchModal = false
                            }
                        },
                        onSelectEntry: { entry in
                            appState.highlightedEntry = entry
                        },
                        onSelectFootprint: { fp in
                            inspectingSearchFootprint = fp
                        },
                        onSelectWish: { wish in
                            inspectingSearchWish = wish
                        },
                        onSelectProject: { proj in
                            inspectingSearchProject = proj
                        }
                    )
                }
                .zIndex(120)
            }

            // 生活刻度统计弹窗 (⌘⌥S)
            if appState.showStatsSheet {
                PaperModalOverlay(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        appState.showStatsSheet = false
                    }
                }) {
                    StatsModalView(appState: appState) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appState.showStatsSheet = false
                        }
                    }
                }
                .zIndex(115)
            }

            // 全局统一纸本确认 / 警示弹窗 (对标 Web ConfirmDialog.vue)
            if let req = appState.activeConfirmDialog {
                PaperConfirmDialogView(request: req) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        appState.activeConfirmDialog = nil
                    }
                }
                .zIndex(130)
            }
        }

        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)

        .sheet(item: $appState.editingEntry) { entry in
            editEntrySheet(entry: entry)
        }
        .sheet(item: $appState.editingTransaction) { tx in
            EditTransactionSheet(appState: appState, transaction: tx) {
                appState.editingTransaction = nil
                Task { @MainActor in
                    // 同样改为增量刷新（账目在时间流里是合成条目，需一并更新）
                    await appState.loadTransactionsAndAssets(forceFull: false)
                    await appState.loadEntries(forceFull: false)
                }
            }
        }
        .sheet(item: $appState.highlightedEntry) { entry in
            entryDetailSheet(entry: entry)
        }
        .sheet(item: $inspectingSearchFootprint) { fp in
            searchFootprintDetailSheet(fp: fp)
        }
        .sheet(item: $inspectingSearchWish) { wish in
            searchWishDetailSheet(wish: wish)
        }
        .sheet(item: $inspectingSearchProject) { project in
            searchProjectDetailSheet(project: project)
        }
        .onAppear {
            visitedSections.insert(appState.activeSection)
        }
        .onChange(of: appState.activeSection) { _, newSec in
            visitedSections.insert(newSec)
        }
        // ESC 统一在最外层处理：按「最上层优先」关闭自定义弹层，
        // 避免每个弹窗各自实现一套 ESC 逻辑而产生不一致。
        .onExitCommand {
            if appState.activeConfirmDialog != nil {
                appState.dismissConfirm()
            } else if appState.showSearchModal {
                withAnimation(.easeInOut(duration: 0.16)) { appState.showSearchModal = false }
            } else if appState.showStatsSheet {
                withAnimation(.easeInOut(duration: 0.16)) { appState.showStatsSheet = false }
            } else if appState.showNewEntrySheet {
                withAnimation(.easeInOut(duration: 0.16)) { appState.showNewEntrySheet = false }
            } else if appState.lightboxAttachment != nil {
                appState.lightboxAttachment = nil
            }
        }
    }

    // MARK: - 主画布内容分发 (保持已访问视图驻留，实现零延迟丝滑切换与滚动位置保持)

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
        case .preferences:
            SettingsView(appState: appState, pinnedTab: .general)
        case .hub:
            SettingsView(appState: appState, pinnedTab: .devices)
        case .storage:
            SettingsView(appState: appState, pinnedTab: .backup)
        case .categories:
            SettingsView(appState: appState, pinnedTab: .categories)
        case .about:
            SettingsView(appState: appState, pinnedTab: .about)
        }
    }

    // MARK: - 左侧工作台导航栏

    private var workbenchSidebar: some View {
        WorkbenchSidebar(
            appState: appState,
            isSystemGroupCollapsed: $isSystemGroupCollapsed,
            onSelect: { section in
                guard appState.activeSection != section else { return }
                visitedSections.insert(section)
                withAnimation(.easeInOut(duration: 0.12)) {
                    appState.activeSection = section
                }
            }
        )
    }
    // MARK: - 右侧时间流主画布

    private var streamTimelineCanvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. 刊头诗意排版 (严格对标 Web HomeView.vue 刊头)
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
                    }

                    if !appState.profile.motto.isEmpty {
                        Text("“\(appState.profile.motto)”")
                            .font(ArchiveTypography.editorialSerif(size: 13))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .italic()
                            .padding(.top, 1)
                    }

                    // 检索与操作胶囊工具条
                    HStack(spacing: 8) {
                        // 模糊搜索框 (⌘F)
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(isSearchFocused ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                            TextField("即时搜索散页与票根… (⌘F)", text: $localSearchText)
                                .accessibilityLabel("搜索散页与票根")
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.bodySans(size: 12))
                                .focused($isSearchFocused)
                                .frame(width: isSearchFocused ? 260 : 200)
                                .animation(.easeOut(duration: 0.16), value: isSearchFocused)
                                .onChange(of: localSearchText) { _, newVal in
                                    // 关键：**任何**变化都要先清掉旧的跨模块命中。
                                    // 原先只在清空时清，于是输入新词之后、
                                    // 新结果返回之前，横幅里显示的还是**上一个关键词**
                                    // 命中的足迹/心愿/项目。
                                    appState.globalSearchResult = nil
                                    if newVal.isEmpty {
                                        appState.searchQuery = ""
                                    }
                                }
                                .task(id: localSearchText) {
                                    guard !localSearchText.isEmpty else { return }
                                    do {
                                        try await Task.sleep(nanoseconds: 180_000_000)
                                        appState.searchQuery = localSearchText
                                        await appState.performGlobalSearch(query: localSearchText)
                                    } catch {}
                                }
                            if appState.isGlobalSearching {
                                ProgressView()
                                    .controlSize(.mini)
                                    .padding(.trailing, 2)
                            }
                            if !localSearchText.isEmpty {
                                Button {
                                    localSearchText = ""
                                    appState.searchQuery = ""
                                    appState.globalSearchResult = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .accessibilityLabel("清空搜索关键词")
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                                .stroke(isSearchFocused ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle.opacity(0.6), lineWidth: isSearchFocused ? 1.0 : 0.5)
                        )
                        .paperElevation(1)

                        // 分类筛选与检索并排：
                        // 早先它们分占两行 —— 左上角一个窄搜索框、右上一排胶囊，
                        // 中间大片空白，视线没有落点。合成一行后，
                        // 左侧「找」与右侧「筛」各占一头，中间留白反而成了呼吸。
                        Spacer(minLength: 24)

                        HStack(spacing: 4) {
                            ForEach(ArchiveCategory.allCases) { cat in
                                if cat != .transaction || appState.isPaired {
                                    PaperPillButton(
                                        title: cat.label,
                                        isSelected: appState.selectedCategory == cat
                                    ) {
                                        guard appState.selectedCategory != cat else { return }
                                        appState.selectedCategory = cat
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 6)

                Divider().overlay(ArchivePalette.borderSubtle)

                // 2. 那年今日 · 岁月回响旧信笺 (复刻 Web 四角切线与朱砂印)
                if !appState.onThisDayEntries.isEmpty {
                    onThisDayBannerCard
                }

                // 3. 迷你山河印谱概览
                miniAtlasWidgetCard

                // 4.1 全库跨模块检索关联发现 (足迹 / 心愿 / 造物)
                if !appState.searchQuery.isEmpty, let res = appState.globalSearchResult,
                   (!res.footprints.isEmpty || !res.wishes.isEmpty || !res.projects.isEmpty) {
                    globalSearchCrossModuleBanner(res: res)
                }

                // 5. 按照事件的树图（时间轴）/ 事件树谱全景
                HStack(alignment: .center) {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text(streamTimelineMode == .treeTimeline ? "事件树状时间轴" : "事件树谱全景图")
                            .font(ArchiveTypography.editorialSerif(size: 13, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        ForEach(StreamTimelineDisplayMode.allCases) { mode in
                            PaperPillButton(
                                title: mode.rawValue,
                                isSelected: streamTimelineMode == mode
                            ) {
                                streamTimelineMode = mode
                            }
                        }
                    }
                }
                .padding(.top, 4)

                if streamTimelineMode == .treeDiagram {
                    EventTreeDiagramView(entries: appState.entries) { selectedEntry in
                        appState.highlightedEntry = selectedEntry
                    }
                } else {
                    let rows = appState.streamRows
                    if rows.isEmpty {
                        // 加载中显示骨架屏（而非空态），避免用户误以为数据丢失
                        if appState.isLoading {
                            ArchiveSkeletonView(rowCount: 4)
                        } else {
                            emptyStreamPlaceholder
                        }
                    } else {
                        // 纵向事件树状时间轴 (含连续树干、直角树枝引线与 >= 14 天岁月年轮切线)
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(rows) { row in
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
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollPosition(id: $keyboardScrollPosition)
        .onChange(of: appState.searchFocusRequest) { _, _ in
            // 切回时间流后等一帧再聚焦，避免视图尚未可见时 FocusState 不生效
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                isSearchFocused = true
            }
        }
        // 深链 / 外部请求打开某条散页时，唤起独立详情窗口
        .onChange(of: appState.detailWindowEntry?.id) { _, newValue in
            guard newValue != nil else { return }
            openWindow(id: "detail")
        }
        .onChange(of: appState.keyboardFocusedEntryId) { _, newValue in
            guard let id = newValue else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                keyboardScrollPosition = id
            }
        }
    }

    /// 条目卡片的行为集合
    ///
    /// **整轮时间流共享同一个实例**（引用类型）。
    /// 早先这里是 `timelineActions(for:)` 逐卡构造值类型闭包集合，
    /// 于是每次父视图重算，每张卡拿到的都是一份全新闭包 → 视图值必变 →
    /// SwiftUI 无法跳过任何一张卡 → 点一下与时间流无关的弹窗，
    /// 整列 60 张卡全部重绘（实测 192ms）。
    /// 共享引用后，只有真正变化的卡片才重绘。
    ///
    /// 必须用 `@State` 持有：`let` 存储属性会随 View 结构体的每次重建而
    /// 重新初始化，引用一变，SwiftUI 依旧要重绘全部卡片。
    /// `@State` 持有引用类型时，SwiftUI 会跨重建保留**同一个实例**。
    @State private var timelineActions = TimelineEntryActions()

    /// 查出条目关联的账目（伴生条目的 id 可能是合成的负数，需归一）
    private func matchingTransaction(for entry: LifeEntry) -> Transaction? {
        if let associated = entry.associatedTransactionId {
            return appState.transactionById[Int(associated)]
        }
        if entry.type == "transaction" {
            return appState.transactionById[entry.id]
        }
        return nil
    }

    // MARK: - 单条散页卡片渲染组件 (TimelineEntryCardView)

    // MARK: - 空态与顶部横幅

    private var emptyStreamPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ArchivePalette.inkMuted)
            Text("散页手记尚待落墨")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .medium))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Text("记录真实可感的当下")
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

    /// 顶部提示条
    ///
    /// 关键：`onDismiss` 由调用方传入，**每条只关自己那一条**。
    /// 原先在这里一次清掉 statusBanner + errorBanner + localDataWarning 三条 ——
    /// 而 localDataWarning 的定义是「需用户手动关闭」，
    /// 于是点任意一条提示的「关闭」，把另两条也一并带走了。
    private func topNoticeStrip(text: String, isError: Bool, onDismiss: @escaping () -> Void) -> some View {
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
            .foregroundStyle(ArchivePalette.inkMuted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(ArchivePalette.archiveSubtle)
    }

    // MARK: - 那年今日 · 岁月回响旧信笺 (复刻 Web 四角切线与朱砂印)
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
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title.isEmpty ? (entry.content.isEmpty ? "无题散页" : entry.content) : entry.title)
                                    .font(ArchiveTypography.editorialSerif(size: 13, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                    .lineLimit(1)

                                Text(entry.content)
                                    .font(ArchiveTypography.bodySans(size: 11))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(entry.parsedDate.dotDate)
                                .font(ArchiveTypography.monoScale(size: 10.5))
                                .foregroundStyle(ArchivePalette.accentWarm)
                        }
                        .padding(8)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.highlightedEntry = entry
                        }
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

            // 四角复古裁切基准线 ⌜ ⌝ ⌞ ⌟
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
        }
    }

    // MARK: - 3. 迷你山河印谱概览 (MiniAtlasWidget)
    @ViewBuilder
    private var miniAtlasWidgetCard: some View {
        let litCities = Array(Set(appState.footprints.map { $0.cityName }))
        if !litCities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "map")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text("山川印谱概览 · 已踏访 \(litCities.count) 座城邑 (\(appState.footprints.count) 次履迹)")
                            .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                    }

                    Spacer()

                    Button {
                        appState.activeSection = .atlas
                    } label: {
                        HStack(spacing: 3) {
                            Text("翻阅全谱与票根")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                        }
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    }
                    .buttonStyle(.plain)
                }

                // 最近踏足城市标签流
                HStack(spacing: 6) {
                    ForEach(appState.footprints.prefix(6)) { fp in
                        Button {
                            appState.activeSection = .atlas
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                                Text(fp.cityName)
                                    .font(ArchiveTypography.monoScale(size: 10.5))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .background(ArchivePalette.archiveSubtle.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
            )
        }
    }




    private func editEntrySheet(entry: LifeEntry) -> some View {
        EditEntrySheetView(entry: entry) { updated in
            // 不要 try?：失败必须抛回弹窗，由弹窗就地展示并保持打开。
            _ = try await APIClient.shared.updateEntry(id: entry.id, updated)
            // 关键：改成**增量**刷新。原先 forceFull: true 会重新拉取并排序
            // 全部条目，档案稍多时点一次「修改」就要等好几秒。
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
            onEditEntry: { appState.editingEntry = $0 },
            onEditTransaction: { appState.editingTransaction = $0 },
            onDeleteTransaction: { appState.deleteTransactionAction($0) }
        )
        .frame(width: 540)
        .background(ArchivePalette.archivePaper)
    }

    // MARK: - 全库跨模块关联检索发现 (Global Search Cross-Module Discovery)

    private func globalSearchCrossModuleBanner(res: GlobalSearchResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Text("全库关联发现")
                    .font(ArchiveTypography.editorialSerif(size: 14, weight: .bold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Text("跨模块命中 \(res.footprints.count + res.wishes.count + res.projects.count) 项")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)

                Spacer()

                Button {
                    appState.activeSection = .atlas
                } label: {
                    HStack(spacing: 4) {
                        Text("前往探索全库")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                }
                .buttonStyle(.plain)
            }

            // 1. 足迹发现
            if !res.footprints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("山川行迹票根 (\(res.footprints.count))")
                        .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(res.footprints) { fp in
                                Button {
                                    inspectingSearchFootprint = fp
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(.system(size: 10))
                                            .foregroundStyle(ArchivePalette.accentWarm)
                                        Text(fp.cityName.isEmpty ? fp.cityCode : fp.cityName)
                                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        if let title = fp.title, !title.isEmpty {
                                            Text("· \(title)")
                                                .font(ArchiveTypography.bodySans(size: 11.5))
                                                .foregroundStyle(ArchivePalette.inkSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // 2. 心愿发现
            if !res.wishes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("三维心愿单 (\(res.wishes.count))")
                        .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(res.wishes) { wish in
                                Button {
                                    inspectingSearchWish = wish
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: wish.status == "fulfilled" ? "checkmark.circle.fill" : "sparkles")
                                            .font(.system(size: 10))
                                            .foregroundStyle(wish.status == "fulfilled" ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                                        Text(wish.title)
                                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                            .lineLimit(1)
                                        if wish.budget > 0 {
                                            Text(FormatUtils.formattedYuan(cents: wish.budget, includeSymbol: true))
                                                .font(ArchiveTypography.monoScale(size: 11))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // 3. 造物发现
            if !res.projects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("造物与项目 (\(res.projects.count))")
                        .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(res.projects) { project in
                                Button {
                                    inspectingSearchProject = project
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "hammer.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                        Text(project.title)
                                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                            .lineLimit(1)
                                        if let sub = project.subtitle, !sub.isEmpty {
                                            Text("· \(sub)")
                                                .font(ArchiveTypography.bodySans(size: 11.5))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(ArchivePalette.archiveSubtle.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.md)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 1)
        )
    }

    private func searchFootprintDetailSheet(fp: Footprint) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("山川行迹 · 票根")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Spacer()
                Button("关闭") {
                    inspectingSearchFootprint = nil
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(fp.title?.isEmpty == false ? fp.title! : fp.cityName)
                    .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                HStack(spacing: 8) {
                    Text(fp.cityName.isEmpty ? fp.cityCode : "\(fp.cityName) (\(fp.cityCode))")
                        .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Text("· 到访：\(FormatUtils.formatDate(fp.visitedAt))")
                        .font(ArchiveTypography.monoScale(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    if let dep = fp.departedAt, !dep.isEmpty {
                        Text("至 \(FormatUtils.formatDate(dep))")
                            .font(ArchiveTypography.monoScale(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
            }

            if let note = fp.note, !note.isEmpty {
                Text(note)
                    .font(ArchiveTypography.bodySans(size: 13.5))
                    .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.9))
                    .padding(.top, 4)
            }

            HStack {
                Button("前往山川行迹查看全部 →") {
                    inspectingSearchFootprint = nil
                    appState.activeSection = .atlas
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 480)
        .background(ArchivePalette.archivePaper)
    }

    private func searchWishDetailSheet(wish: Wish) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(wish.kind == "travel" ? "旅程愿望" : (wish.kind == "milestone" ? "里程碑" : "心愿单"))
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Spacer()
                Button("关闭") {
                    inspectingSearchWish = nil
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(wish.title)
                    .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                HStack(spacing: 10) {
                    Text(wish.status == "fulfilled" ? "已圆满" : "待实现")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(wish.status == "fulfilled" ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    if wish.budget > 0 {
                        Text("预算 \(FormatUtils.formattedYuan(cents: wish.budget, includeSymbol: true))")
                            .font(ArchiveTypography.monoScale(size: 12))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }

                    if let target = wish.targetDate, !target.isEmpty {
                        Text("目标 \(FormatUtils.formatDate(target))")
                            .font(ArchiveTypography.monoScale(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
            }

            if let spec = wish.spec, !spec.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("规格与意向")
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Text(spec)
                        .font(ArchiveTypography.bodySans(size: 12.5))
                        .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.85))
                }
            }

            if let note = wish.note, !note.isEmpty {
                Text(note)
                    .font(ArchiveTypography.bodySans(size: 13))
                    .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.9))
            }

            HStack {
                Button("前往心愿清单查看全部 →") {
                    inspectingSearchWish = nil
                    appState.activeSection = .wishes
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 480)
        .background(ArchivePalette.archivePaper)
    }

    private func searchProjectDetailSheet(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("造物与项目")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Spacer()
                Button("关闭") {
                    inspectingSearchProject = nil
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(project.title)
                    .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                if let sub = project.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(ArchiveTypography.bodySans(size: 13, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                }

                HStack(spacing: 8) {
                    if let cat = project.category, !cat.isEmpty {
                        Text(cat)
                            .font(ArchiveTypography.bodySans(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if let st = project.status, !st.isEmpty {
                        Text(st)
                            .font(ArchiveTypography.monoScale(size: 11))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }
                }
            }

            if !project.description.isEmpty {
                Text(project.description)
                    .font(ArchiveTypography.bodySans(size: 13))
                    .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.9))
            }

            if let story = project.story, !story.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("造物始末与手记")
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Text(story)
                        .font(ArchiveTypography.bodySans(size: 12.5))
                        .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.85))
                }
            }

            HStack {
                Button("前往岁时造物查看全部 →") {
                    inspectingSearchProject = nil
                    appState.activeSection = .projects
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 480)
        .background(ArchivePalette.archivePaper)
    }

    // MARK: - 暗房全屏看图灯箱 (EditorialLightboxView)
}
