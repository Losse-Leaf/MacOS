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


    // 键盘流与检索状态
    @State private var keyboardScrollPosition: Int?
    @State private var localSearchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var isOnThisDayExpanded: Bool = true

    // 管理模式：编辑与删除状态
    @State private var editingEntry: LifeEntry?
    @State private var editingTransaction: Transaction?
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
                    if let banner = appState.statusBanner {
                        topNoticeStrip(text: banner, isError: false)
                    } else if let err = appState.errorBanner {
                        topNoticeStrip(text: err, isError: true)
                    }

                    ZStack {
                        ForEach(WorkbenchSection.allCases) { section in
                            if visitedSections.contains(section) {
                                sectionContentView(for: section)
                                    .opacity(appState.activeSection == section ? 1 : 0)
                                    .allowsHitTesting(appState.activeSection == section)
                                    .zIndex(appState.activeSection == section ? 1 : 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.12), value: appState.activeSection)

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
            if appState.showSettingsSheet {
                ZStack {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.showSettingsSheet = false
                            }
                        }

                    SettingsView(appState: appState)
                        .frame(width: 820, height: 580)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(ArchivePalette.borderSubtle, lineWidth: 1)
                        )
                        .onTapGesture {
                            // 吸收卡片内部的点击，防止误触发背景退出
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        ))
                }
                .zIndex(100)
            }

            // 全局快捷悬浮发布按钮 (Floating Action Button)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        appState.showNewEntrySheet = true
                        AudioFeedback.shared.playTink()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ArchivePalette.archivePaper)
                            .frame(width: 44, height: 44)
                            .background(ArchivePalette.inkPrimary)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(24)
                    .help("记一笔 (⌘N)")
                }
            }
            .allowsHitTesting(!appState.showSettingsSheet && !appState.showNewEntrySheet && !appState.showSearchModal && !appState.showStatsSheet)

            if appState.showNewEntrySheet {
                ZStack {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.showNewEntrySheet = false
                            }
                        }

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
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 1)
                    )
                    .onTapGesture {
                        // 吸收点击
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    ))
                }
                .zIndex(110)
            }

            // 全局聚光灯档案检索 (⌘K Spotlight)
            if appState.showSearchModal {
                ZStack {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.showSearchModal = false
                            }
                        }

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
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 1)
                    )
                    .onTapGesture {
                        // 吸收点击
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    ))
                }
                .zIndex(120)
            }

            // 生活刻度统计弹窗 (⌘⌥S)
            if appState.showStatsSheet {
                ZStack {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.showStatsSheet = false
                            }
                        }

                    StatsModalView(appState: appState) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appState.showStatsSheet = false
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 1)
                    )
                    .onTapGesture {
                        // 吸收点击
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    ))
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

        .sheet(item: $editingEntry) { entry in
            editEntrySheet(entry: entry)
        }
        .sheet(item: $editingTransaction) { tx in
            EditTransactionSheet(appState: appState, transaction: tx) {
                editingTransaction = nil
                Task { @MainActor in
                    await appState.loadTransactionsAndAssets(forceFull: true)
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
        .task {
            await appState.refreshAll()
        }
        .onAppear {
            visitedSections.insert(appState.activeSection)
        }
        .onChange(of: appState.activeSection) { _, newSec in
            visitedSections.insert(newSec)
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
        case .settings:
            SettingsView(appState: appState)
        case .darkroom:
            DarkroomDropZone(appState: appState)
        case .creations:
            ProjectsWishesView(appState: appState)
        }
    }

    // MARK: - 左侧工作台导航栏

    private var workbenchSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 刊头印记 (100% 动态读取后端配置与主理人档案)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(ArchivePalette.accentMoss)
                    Text(appState.siteConfig.siteName.isEmpty ? "散页 · 时光手账" : appState.siteConfig.siteName)
                        .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                }

                if !appState.profile.name.isEmpty || !appState.profile.displayCity.isEmpty {
                    Text(
                        [appState.profile.name, appState.profile.displayCity]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                    )
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 44)
            .overlay(
                WindowDragHandleView()
                    .frame(height: 38),
                alignment: .top
            )

            Divider().overlay(ArchivePalette.borderSubtle)

            // 全局档案检索快捷按钮 (⌘K)
            Button {
                appState.showSearchModal = true
                AudioFeedback.shared.playTink()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Text("全局档案检索…")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Spacer()
                    Text("⌘K")
                        .font(ArchiveTypography.monoScale(size: 9.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ArchivePalette.archiveSubtle.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)

            // 导航菜单项
            VStack(alignment: .leading, spacing: 4) {
                ForEach(WorkbenchSection.sidebarSections) { section in
                    WorkbenchNavRow(
                        section: section,
                        selected: appState.activeSection == section
                    ) {
                        guard appState.activeSection != section else { return }
                        visitedSections.insert(section)
                        withAnimation(.easeInOut(duration: 0.12)) {
                            appState.activeSection = section
                        }
                        AudioFeedback.shared.playTink()
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // 底部配置中心入口与系统状态
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))

                // 生活刻度统计入口 (⌘⌥S)
                Button {
                    appState.showStatsSheet = true
                    AudioFeedback.shared.playTink()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 12))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                        Text("生活统计")
                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Spacer()
                        Text("⌘⌥S")
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ArchivePalette.archivePaper.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s", modifiers: [.command, .option])

                // 原生偏好设置/配置中心入口 (⌘,)
                Button {
                    appState.showSettingsSheet = true
                    AudioFeedback.shared.playTink()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                        Text("配置中心")
                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Spacer()
                        Text("⌘,")
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ArchivePalette.archivePaper.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: [.command])

                // 中枢就绪状态与快捷记账提示
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.isOnline ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .frame(width: 5, height: 5)
                    Text(appState.isOnline ? (appState.isFlushingOutbox ? "同步中…" : "中枢就绪") : "离线发件箱守护")
                        .font(ArchiveTypography.bodySans(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    Spacer()

                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text("快速记 ⇧⌘L")
                    }
                    .font(ArchiveTypography.monoScale(size: 9.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .background(ArchivePalette.archivePaper.opacity(0.65))
    }

    private func metricMiniItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(ArchiveTypography.monoScale(size: 13.5, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Text(label)
                .font(ArchiveTypography.bodySans(size: 10.5))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
    }

    /// 侧边导航行：整行可点（contentShape 修透明背景不参与命中测试的问题），
    /// 悬停显背景、选中态 0.14s 局部过渡——反馈即时且动画不外溢全树。
    private struct WorkbenchNavRow: View {
        let section: WorkbenchSection
        let selected: Bool
        let action: () -> Void

        @State private var isHovering: Bool = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: section.icon)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                        .frame(width: 18)
                    Text(section.title)
                        .font(ArchiveTypography.bodySans(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? ArchivePalette.inkPrimary : ArchivePalette.inkSecondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(rowFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(selected ? ArchivePalette.borderDivider : Color.clear, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.14), value: selected)
            .animation(.easeOut(duration: 0.1), value: isHovering)
            .onHover { isHovering = $0 }
        }

        private var rowFill: Color {
            if selected { return ArchivePalette.archiveSubtle }
            return isHovering ? ArchivePalette.archiveSubtle.opacity(0.45) : .clear
        }
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
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.bodySans(size: 12))
                                .focused($isSearchFocused)
                                .frame(width: isSearchFocused ? 260 : 200)
                                .animation(.easeOut(duration: 0.16), value: isSearchFocused)
                                .onChange(of: localSearchText) { _, newVal in
                                    if newVal.isEmpty {
                                        appState.searchQuery = ""
                                        appState.globalSearchResult = nil
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
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                        .paperElevation(1)

                        Spacer()

                        Button {
                            exportMarkdown()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                        .paperElevation(1)
                        .help("导出当前视图为 Markdown")

                        Button {
                            Task { @MainActor in
                                await appState.refreshAll(forceFull: true)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                        .paperElevation(1)
                        .help("全量同步中枢档案 (⌘R)")

                        Button {
                            appState.showNewEntrySheet = true
                            AudioFeedback.shared.playTink()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 11))
                                Text("记一笔")
                                    .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .foregroundStyle(ArchivePalette.archivePaper)
                            .background(ArchivePalette.inkPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                        }
                        .buttonStyle(.plain)
                        .paperElevation(1)
                        .keyboardShortcut("n", modifiers: [.command])
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


                // 4. 四维母体分类切换栏与 #标签 筛选
                HStack(spacing: 6) {
                    ForEach(ArchiveCategory.allCases) { cat in
                        if cat != .transaction || appState.isPaired {
                            PaperPillButton(
                                title: cat.label,
                                isSelected: appState.selectedCategory == cat
                            ) {
                                guard appState.selectedCategory != cat else { return }
                                appState.selectedCategory = cat
                                AudioFeedback.shared.playTink()
                            }
                        }
                    }

                    Spacer()
                }

                // 4.1 全库跨模块检索关联发现 (足迹 / 心愿 / 造物)
                if !appState.searchQuery.isEmpty, let res = appState.globalSearchResult,
                   (!res.footprints.isEmpty || !res.wishes.isEmpty || !res.projects.isEmpty) {
                    globalSearchCrossModuleBanner(res: res)
                }

                // 5. 纵向时间流条目列表 (含 >= 14 天岁月留白切线)
                let list = appState.filteredStreamEntries
                if list.isEmpty {
                    emptyStreamPlaceholder
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                let prev = list[index - 1]
                                let gapDays = FormatUtils.daysBetween(prev.occurredAt, entry.occurredAt)
                                if gapDays >= 14 {
                                    TemporalGapDivider(days: gapDays)
                                }
                            }
                            TimelineEntryCardView(
                                entry: entry,
                                appState: appState,
                                onEditEntry: { editingEntry = entry },
                                onDeleteEntry: {
                                    appState.askConfirm(
                                        title: "确认删除该条生活手稿？",
                                        message: "删除后记录将从时间流中移除，关联的附件与下渗足迹将一并清理。",
                                        confirmText: "删除手稿",
                                        danger: true
                                    ) {
                                        deleteEntryAction(entry)
                                    }
                                },
                                onEditTransaction: { tx in editingTransaction = tx },
                                onDeleteTransaction: { tx in
                                    appState.askConfirm(
                                        title: "确认删除该笔流水账目？",
                                        message: "删除后将从本地账本与中枢中移除，月度收支与资产大盘将即刻重新核算。",
                                        confirmText: "删除账目",
                                        danger: true
                                    ) {
                                        deleteTransactionAction(tx)
                                    }
                                },
                                onToggleFeatured: { toggleFeatured(entry) },
                                onOpenDetail: { appState.highlightedEntry = entry; AudioFeedback.shared.playTink() }
                            )
                            .id(entry.id)
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollPosition(id: $keyboardScrollPosition)
        .onChange(of: appState.keyboardFocusedEntryId) { _, newValue in
            guard let id = newValue else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                keyboardScrollPosition = id
            }
        }
    }

    // MARK: - 单条散页卡片渲染组件 (TimelineEntryCardView)

    struct TimelineEntryCardView: View {
        let entry: LifeEntry
        @Bindable var appState: AppState
        var onEditEntry: () -> Void
        var onDeleteEntry: () -> Void
        var onEditTransaction: (Transaction) -> Void
        var onDeleteTransaction: (Transaction) -> Void
        var onToggleFeatured: () -> Void
        var onOpenDetail: () -> Void

        @State private var isHovering: Bool = false

        private var parsed: FormatUtils.ParsedBeijingDate {
            entry.parsedDate
        }

        private var typeAccentColor: Color {
            switch entry.type {
            case "travel": return ArchivePalette.accentWarm
            case "project": return Color("SpectrumStudy", bundle: ArchiveResourceBundle.bundle)
            case "wish": return Color("SpectrumLeisure", bundle: ArchiveResourceBundle.bundle)
            case "transaction": return Color("SpectrumDining", bundle: ArchiveResourceBundle.bundle)
            default: return ArchivePalette.accentMoss
            }
        }

        private var entryTypeBadgeName: String {
            switch entry.type {
            case "travel": return "山川游历"
            case "project": return "造物演进"
            case "wish": return "心愿印记"
            case "transaction": return "柴米油盐"
            default: return "日常随笔"
            }
        }

        var body: some View {
            HStack(alignment: .top, spacing: 0) {
                // 左侧时光彩色印线 (2.5pt 细微边缘色标)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(typeAccentColor.opacity(0.85))
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.trailing, 14)

                VStack(alignment: .leading, spacing: 10) {
                    // 顶栏：形态印章 + 北京时间戳 + 地点 + 悬停优雅动作
                    HStack(spacing: 8) {
                        Text(entryTypeBadgeName)
                            .font(ArchiveTypography.monoScale(size: 10.5, weight: .medium))
                            .foregroundStyle(typeAccentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(typeAccentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                        Text(parsed.dotDateTime)
                            .font(ArchiveTypography.monoScale(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)

                        if let loc = entry.location ?? entry.cityName, !loc.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "location")
                                    .font(.system(size: 9.5))
                                Text(loc)
                                    .font(ArchiveTypography.bodySans(size: 11))
                            }
                            .foregroundStyle(ArchivePalette.inkMuted)
                        }

                        if entry.featured == true {
                            Text("精选")
                                .font(ArchiveTypography.monoScale(size: 10, weight: .medium))
                                .foregroundStyle(ArchivePalette.accentMoss)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                        .stroke(ArchivePalette.accentMoss.opacity(0.4), lineWidth: 0.5)
                                )
                        }

                        if (entry.syncStatus ?? "synced") != "synced" {
                            Text("待同步")
                                .font(ArchiveTypography.monoScale(size: 10))
                                .foregroundStyle(ArchivePalette.accentWarm)
                        }

                        Spacer()

                        // 右侧操作：仅在鼠标悬停时优雅淡现，默认保持日记纯粹无噪点
                        HStack(spacing: 6) {
                            if isHovering {
                                if entry.type == "transaction" {
                                    let txId = entry.associatedTransactionId ?? Int64(entry.id)
                                    if let tx = appState.transactions.first(where: { $0.id == txId }) {
                                        Button {
                                            onEditTransaction(tx)
                                        } label: {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 11))
                                                .foregroundStyle(ArchivePalette.inkSecondary)
                                                .frame(width: 24, height: 24)
                                                .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("编辑账目")

                                        Button {
                                            onDeleteTransaction(tx)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundStyle(ArchivePalette.accentWarm)
                                                .frame(width: 24, height: 24)
                                                .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("删除账目")
                                    }
                                } else {
                                    Button {
                                        onToggleFeatured()
                                    } label: {
                                        Image(systemName: entry.featured == true ? "star.fill" : "star")
                                            .font(.system(size: 11))
                                            .foregroundStyle(entry.featured == true ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                                            .frame(width: 24, height: 24)
                                            .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help(entry.featured == true ? "取消精选" : "设为精选")

                                    Button {
                                        onEditEntry()
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 11))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                            .frame(width: 24, height: 24)
                                            .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("编辑手稿")

                                    Button {
                                        onDeleteEntry()
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundStyle(ArchivePalette.accentWarm)
                                            .frame(width: 24, height: 24)
                                            .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("删除手稿")
                                }
                            }

                            Button {
                                onOpenDetail()
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .frame(width: 24, height: 24)
                                    .background(isHovering ? ArchivePalette.archiveSubtle.opacity(0.8) : Color.clear)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("查看手稿完整详情")
                        }
                        .animation(.easeInOut(duration: 0.15), value: isHovering)
                    }

                    if !entry.title.isEmpty {
                        Text(entry.title)
                            .font(ArchiveTypography.editorialSerif(size: 17.5, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                    }

                    Text(LocalizedStringKey(entry.content))
                        .font(ArchiveTypography.bodySans(size: 13.5))
                        .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.92))
                        .lineSpacing(5)
                        .textSelection(.enabled)

                    // 附件胶片相框画廊 (.film-frame)
                    if !entry.attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(entry.attachments) { att in
                                    if let url = APIClient.shared.resolveMediaURL(att.url) {
                                        FilmFrameView(
                                            imageURL: url,
                                            caption: entry.title.isEmpty ? att.originalFilename : entry.title,
                                            metaText: parsed.dotDate,
                                            maxHeight: 220
                                        ) {
                                            appState.lightboxAttachment = att
                                            AudioFeedback.shared.playTink()
                                        }
                                        .frame(width: 260)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(16)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
            .paperElevation(isHovering ? 2 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.md)
                    .stroke(
                        appState.keyboardFocusedEntryId == entry.id ? ArchivePalette.accentWarm : Color.clear,
                        lineWidth: 1.0
                    )
            )
            .onHover { isHovering = $0 }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onOpenDetail()
            }
            .contextMenu {
                if entry.type == "transaction" {
                    let txId = entry.associatedTransactionId ?? Int64(entry.id)
                    if let tx = appState.transactions.first(where: { $0.id == txId }) {
                        Button {
                            onEditTransaction(tx)
                        } label: {
                            Label("编辑账目", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDeleteTransaction(tx)
                        } label: {
                            Label("删除账目", systemImage: "trash")
                        }
                        Divider()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(FormatUtils.formattedYuan(cents: tx.amount), forType: .string)
                            AudioFeedback.shared.playTink()
                            appState.showTemporaryBanner("已拷贝金额至剪贴板")
                        } label: {
                            Label("拷贝金额", systemImage: "doc.on.doc")
                        }
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(tx.title.isEmpty ? tx.category : tx.title, forType: .string)
                            AudioFeedback.shared.playTink()
                            appState.showTemporaryBanner("已拷贝账目摘要至剪贴板")
                        } label: {
                            Label("拷贝账目摘要", systemImage: "text.quote")
                        }
                    }
                } else {
                    Button {
                        onOpenDetail()
                    } label: {
                        Label("查看手稿详情", systemImage: "book.pages")
                    }
                    Button {
                        onToggleFeatured()
                    } label: {
                        Label(entry.featured == true ? "取消精选印记" : "标记为精选印记", systemImage: entry.featured == true ? "star.slash" : "star")
                    }
                    Button {
                        onEditEntry()
                    } label: {
                        Label("编辑手稿", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDeleteEntry()
                    } label: {
                        Label("删除手稿", systemImage: "trash")
                    }
                    Divider()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.content, forType: .string)
                        AudioFeedback.shared.playTink()
                        appState.showTemporaryBanner("已拷贝手稿正文至剪贴板")
                    } label: {
                        Label("拷贝手稿正文", systemImage: "doc.on.doc")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(parsed.dotDateTime, forType: .string)
                        AudioFeedback.shared.playTink()
                        appState.showTemporaryBanner("已拷贝时间戳至剪贴板")
                    } label: {
                        Label("拷贝时间戳", systemImage: "clock")
                    }
                }
            }
            .paperHover()
        }
    }

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

    private func updateAvailableStrip(update: UpdateChecker.ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(ArchivePalette.accentWarm)
                Text("发现新版本 \(update.tagName)（当前版本 v\(UpdateChecker.shared.currentVersion)）")
                    .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Spacer()

                if UpdateChecker.shared.isUpdating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在下载更新 (\(Int(UpdateChecker.shared.updateProgress * 100))%)…")
                            .font(ArchiveTypography.monoScale(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }
                } else {
                    Button("浏览器下载") {
                        UpdateChecker.shared.openDownloadInBrowser()
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .help("在浏览器直接下载新版 DMG / ZIP 安装包")

                    Button("终端极速更新") {
                        UpdateChecker.shared.copyInstallCommandToClipboard()
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .help("复制终端一键全自动安装更新命令")

                    Button("应用内更新") {
                        Task { @MainActor in
                            await UpdateChecker.shared.performInAppUpdate()
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))

                    Button("稍后提醒") {
                        UpdateChecker.shared.availableUpdate = nil
                    }
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .buttonStyle(.plain)
                    .foregroundStyle(ArchivePalette.inkMuted)

                    Button("忽略此版本") {
                        UpdateChecker.shared.ignoreCurrentUpdate()
                    }
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .buttonStyle(.plain)
                    .foregroundStyle(ArchivePalette.inkMuted)
                }
            }

            if let err = UpdateChecker.shared.updateError {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    Text(err)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(ArchivePalette.accentWarm.opacity(0.12))
        .overlay(
            Rectangle()
                .fill(ArchivePalette.accentWarm.opacity(0.3))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func topNoticeStrip(text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(isError ? ArchivePalette.accentWarm : ArchivePalette.accentMoss)
            Text(text)
                .font(ArchiveTypography.bodySans(size: 12))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Spacer()
            Button("关闭") {
                appState.statusBanner = nil
                appState.errorBanner = nil
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
                            AudioFeedback.shared.playPaperFlip()
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
                        AudioFeedback.shared.playPaperFlip()
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
                            AudioFeedback.shared.playPaperFlip()
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







    /// 导出当前筛选视图为 Markdown 档案（NSSavePanel 落盘）
    private func exportMarkdown() {
        let entries = appState.filteredStreamEntries
        guard !entries.isEmpty else { return }
        let markdown = ArchiveExporter.makeMarkdown(entries: entries)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "looseleaf-export-\(FormatUtils.beijingDateString()).md"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                AudioFeedback.shared.playShutter()
            } catch {
                appState.errorBanner = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private func toggleFeatured(_ entry: LifeEntry) {
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
            _ = try? await APIClient.shared.updateEntry(id: entry.id, req)
            AudioFeedback.shared.playTink()
            await appState.loadEntries(forceFull: true)
        }
    }

    private func deleteEntryAction(_ entry: LifeEntry) {
        guard entry.id > 0 else { return }
        Task { @MainActor in
            _ = try? await APIClient.shared.deleteEntry(id: entry.id)
            AudioFeedback.shared.playPaperFlip()
            await appState.loadEntries(forceFull: true)
            await appState.loadConfigAndProfile()
            if appState.highlightedEntry?.id == entry.id {
                appState.highlightedEntry = nil
            }
        }
    }

    private func deleteTransactionAction(_ tx: Transaction) {
        guard tx.id > 0 else { return }
        Task { @MainActor in
            _ = try? await APIClient.shared.deleteTransaction(id: tx.id)
            AudioFeedback.shared.playPaperFlip()
            await appState.loadTransactionsAndAssets(forceFull: true)
            await appState.loadConfigAndProfile()
            if appState.highlightedEntry?.id == tx.id {
                appState.highlightedEntry = nil
            }
        }
    }

    private func editEntrySheet(entry: LifeEntry) -> some View {
        EditEntrySheetView(entry: entry) { updated in
            Task { @MainActor in
                _ = try? await APIClient.shared.updateEntry(id: entry.id, updated)
                AudioFeedback.shared.playShutter()
                await appState.loadEntries(forceFull: true)
                await appState.loadConfigAndProfile()
                editingEntry = nil
            }
        } onCancel: {
            editingEntry = nil
        }
    }

    private func entryDetailSheet(entry: LifeEntry) -> some View {
        let isTx = (entry.type == "transaction")
        let txId = entry.associatedTransactionId ?? Int64(entry.id)
        let matchingTx = isTx ? appState.transactions.first(where: { $0.id == txId }) : nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(entryTypeBadge(entry.type))
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Text(entry.parsedDate.dotDateTime)
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer()
                if appState.isPaired && (entry.id > 0 || (isTx && matchingTx != nil)) {
                    if isTx {
                        if let tx = matchingTx {
                            Button("编辑账目") {
                                appState.highlightedEntry = nil
                                editingTransaction = tx
                            }
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .buttonStyle(.plain)

                            Button("删除账目") {
                                appState.askConfirm(
                                    title: "确认删除该笔流水账目？",
                                    message: "删除后将从本地账本与中枢中移除，月度收支与资产大盘将即刻重新核算。",
                                    confirmText: "删除账目",
                                    danger: true
                                ) {
                                    deleteTransactionAction(tx)
                                    appState.highlightedEntry = nil
                                }
                            }
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button("编辑手稿") {
                            let target = entry
                            appState.highlightedEntry = nil
                            editingEntry = target
                        }
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .buttonStyle(.plain)

                        Button("删除记录") {
                            appState.askConfirm(
                                title: "确认删除该条生活手稿？",
                                message: "删除后记录将从时间流中移除，关联的附件与下渗足迹将一并清理。",
                                confirmText: "删除手稿",
                                danger: true
                            ) {
                                Task { @MainActor in
                                    try? await APIClient.shared.deleteEntry(id: entry.id)
                                    await appState.loadEntries(forceFull: true)
                                    appState.highlightedEntry = nil
                                }
                            }
                        }
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .buttonStyle(.plain)
                    }
                }
                Button("关闭") {
                    appState.highlightedEntry = nil
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            if let tx = matchingTx {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tx.title.isEmpty ? tx.category : tx.title)
                            .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Spacer()
                        Text("\(tx.type == "income" ? "+" : "-")\(FormatUtils.formattedYuan(cents: tx.amount, includeSymbol: true))")
                            .font(ArchiveTypography.monoScale(size: 22, weight: .bold))
                            .foregroundStyle(tx.type == "income" ? ArchivePalette.accentMoss : ArchivePalette.inkPrimary)
                    }

                    HStack(spacing: 8) {
                        Text(tx.category)
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        if let pay = tx.paymentMethod, !pay.isEmpty {
                            Text(pay)
                                .font(ArchiveTypography.bodySans(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        if tx.isInstallment == true, let months = tx.installmentMonths, months > 0 {
                            Text("分期 \(months) 期")
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(ArchivePalette.accentWarm, lineWidth: 0.5)
                                )
                        }
                    }

                    if let note = tx.note, !note.isEmpty {
                        Text(note)
                            .font(ArchiveTypography.bodySans(size: 13.5))
                            .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.88))
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 8) {
                    if let city = entry.cityName ?? entry.location, !city.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10))
                            Text(city)
                                .font(ArchiveTypography.monoScale(size: 11))
                        }
                        .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    if entry.featured == true {
                        HStack(spacing: 3) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 10))
                            Text("精选典藏")
                                .font(ArchiveTypography.monoScale(size: 11))
                        }
                        .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }

                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(LocalizedStringKey(entry.content))
                            .font(ArchiveTypography.bodySans(size: 14))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        if !entry.attachments.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(entry.attachments) { att in
                                        if let url = APIClient.shared.resolveMediaURL(att.url) {
                                            FilmFrameView(
                                                imageURL: url,
                                                caption: entry.title.isEmpty ? att.originalFilename : entry.title,
                                                metaText: entry.parsedDate.dotDate,
                                                maxHeight: 200
                                            ) {
                                                appState.lightboxAttachment = att
                                                AudioFeedback.shared.playTink()
                                            }
                                            .frame(width: 240)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 420)
            }
        }
        .padding(24)
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
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 480)
        .background(ArchivePalette.archivePaper)
    }

    // MARK: - 暗房全屏看图灯箱 (EditorialLightboxView)

/// 暗房全屏沉浸式看图灯箱：支持触控板双指缩放、拖拽平移、双击 2x 放大、键盘左右键切图与原片系统预览
public struct EditorialLightboxView: View {
    @State private var currentAttachment: Attachment
    let allAttachments: [Attachment]
    var onClose: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var noticeText: String?

    public init(attachment: Attachment, allAttachments: [Attachment], onClose: @escaping () -> Void) {
        _currentAttachment = State(initialValue: attachment)
        self.allAttachments = allAttachments
        self.onClose = onClose
    }

    private var currentIndex: Int {
        allAttachments.firstIndex(where: { $0.id == currentAttachment.id }) ?? 0
    }

    public var body: some View {
        ZStack {
            ArchivePalette.inkPrimary.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture {
                    if scale <= 1.0 {
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.25)) {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                }

            VStack(spacing: 16) {
                if let url = APIClient.shared.resolveMediaURL(currentAttachment.url) {
                    ZStack {
                        FilmFrameView(
                            imageURL: url,
                            caption: currentAttachment.originalFilename,
                            metaText: (currentAttachment.width != nil && currentAttachment.height != nil)
                                ? "\(currentAttachment.width!) × \(currentAttachment.height!) px"
                                : nil,
                            maxHeight: 520
                        )
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(max(value, 0.8), 3.5)
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.25)) {
                                        if scale < 1.0 {
                                            scale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            scale > 1.0 ? DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                } : nil
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.25)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 780)

                    // 左右翻页控制器与相册计数指示
                    if allAttachments.count > 1 {
                        HStack(spacing: 20) {
                            Button {
                                changePhoto(by: -1)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("上一张")
                                }
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .disabled(currentIndex == 0)

                            Text("\(currentIndex + 1) / \(allAttachments.count)")
                                .font(ArchiveTypography.monoScale(size: 12, weight: .semibold))
                                .foregroundStyle(ArchivePalette.archivePaper)

                            Button {
                                changePhoto(by: 1)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("下一张")
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .disabled(currentIndex == allAttachments.count - 1)
                        }
                    }

                    // 动作栏
                    HStack(spacing: 10) {
                        Button {
                            openInSystemPreview(url: url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow.on.rectangle")
                                Text("「预览」查看")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .help("使用 macOS 系统原生 Preview 打开原片")

                        Button {
                            copyImageToClipboard(url: url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("拷贝相纸")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                        Button {
                            saveImageToDisk(url: url, filename: currentAttachment.originalFilename)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                Text("导出存储…")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                        Button("关闭 ESC") {
                            onClose()
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                        .keyboardShortcut(.cancelAction)
                    }

                    if let noticeText {
                        Text(noticeText)
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }
            }
            .padding(24)
        }
    }

    private func changePhoto(by delta: Int) {
        let newIdx = currentIndex + delta
        guard allAttachments.indices.contains(newIdx) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
            currentAttachment = allAttachments[newIdx]
        }
        AudioFeedback.shared.playPaperFlip()
    }

    private func openInSystemPreview(url: URL) {
        Task { @MainActor in
            if let cached = PaperImageCache.image(for: url),
               let tiffData = cached.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? pngData.write(to: tempPath, options: .atomic)
                NSWorkspace.shared.open(tempPath)
                return
            }
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? data.write(to: tempPath, options: .atomic)
                NSWorkspace.shared.open(tempPath)
            }
        }
    }

    private func copyImageToClipboard(url: URL) {
        Task { @MainActor in
            if let cached = PaperImageCache.image(for: url) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([cached])
                AudioFeedback.shared.playTink()
                noticeText = "已拷贝相纸至剪贴板"
                return
            }
            if let (data, _) = try? await URLSession.shared.data(from: url), let img = NSImage(data: data) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([img])
                AudioFeedback.shared.playTink()
                noticeText = "已拷贝相纸至剪贴板"
            }
        }
    }

    private func saveImageToDisk(url: URL, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename.isEmpty ? "looseleaf-photo.jpg" : filename
        if panel.runModal() == .OK, let targetURL = panel.url {
            Task { @MainActor in
                if let (data, _) = try? await URLSession.shared.data(from: url) {
                    try? data.write(to: targetURL, options: .atomic)
                    AudioFeedback.shared.playShutter()
                    noticeText = "相纸已导出落盘"
                }
            }
        }
    }
}

    private func entryTypeBadge(_ raw: String) -> String {
        switch raw {
        case "travel": return "山川游历"
        case "project": return "造物演进"
        case "wish": return "心愿印记"
        case "transaction": return "柴米油盐"
        default: return "日常随笔"
        }
    }
}

/// 修改散页手稿弹窗表单 (EditEntrySheetView)
@MainActor
public struct EditEntrySheetView: View {
    public let entry: LifeEntry
    public var onSave: (UpdateEntryRequest) -> Void
    public var onCancel: () -> Void

    @State private var editTitle: String
    @State private var editContent: String
    @State private var editCityCode: String
    @State private var editCityName: String
    @State private var editFeatured: Bool
    @State private var editAttachments: [Attachment]
    @State private var isUploading: Bool = false

    public init(
        entry: LifeEntry,
        onSave: @escaping (UpdateEntryRequest) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onCancel = onCancel
        _editTitle = State(initialValue: entry.title)
        _editContent = State(initialValue: entry.content)
        _editCityCode = State(initialValue: entry.cityCode ?? "")
        _editCityName = State(initialValue: entry.cityName ?? entry.location ?? "")
        _editFeatured = State(initialValue: entry.featured ?? false)
        _editAttachments = State(initialValue: entry.attachments)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑生活手稿")
                .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("标题", text: $editTitle)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextEditor(text: $editContent)
                .font(ArchiveTypography.bodySans(size: 13))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .padding(6)
                .frame(minHeight: 140)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            PaperCityPicker(selectedCode: $editCityCode, selectedName: $editCityName, placeholder: "选择城市…")

            // 照片相纸附件管理与增删
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("手账影像相纸 (\(editAttachments.count))")
                        .font(ArchiveTypography.editorialSerif(size: 13, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Spacer()

                    if isUploading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("暗房直传中…")
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)
                        }
                    } else {
                        Button("+ 补选相纸照片") {
                            selectPhotosForEdit()
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .controlSize(.small)
                    }
                }

                if !editAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(editAttachments) { att in
                                ZStack(alignment: .topTrailing) {
                                    if let url = APIClient.shared.resolveMediaURL(att.url) {
                                        AsyncImage(url: url) { phase in
                                            if let image = phase.image {
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } else {
                                                ArchivePalette.archiveSubtle
                                            }
                                        }
                                        .frame(width: 68, height: 68)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                                        )
                                    }

                                    Button {
                                        editAttachments.removeAll(where: { $0.id == att.id })
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.white, ArchivePalette.inkPrimary.opacity(0.85))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(2)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            HStack {
                Toggle("标记为精选印记", isOn: $editFeatured)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: 12))

                Spacer()

                Button("取消") {
                    onCancel()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                Button("保存修改 ⌘↩") {
                    let cleanCity = editCityName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let code = editCityCode.isEmpty ? (FormatUtils.resolveCityCode(from: cleanCity) ?? entry.cityCode) : editCityCode
                    let req = UpdateEntryRequest(
                        type: entry.type,
                        title: editTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        content: editContent.trimmingCharacters(in: .whitespacesAndNewlines),
                        occurredAt: entry.occurredAt,
                        location: cleanCity.isEmpty ? nil : cleanCity,
                        featured: editFeatured,
                        cityCode: code,
                        cityName: cleanCity.isEmpty ? nil : cleanCity,
                        attachmentIds: editAttachments.map(\.id)
                    )
                    onSave(req)
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(editContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(ArchivePalette.archivePaper)
    }

    private func selectPhotosForEdit() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .rawImage]
        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            Task { @MainActor in
                isUploading = true
                for url in urls {
                    do {
                        let processed = try await ImageProcessor.processImageFileInBackground(at: url)
                        let att = try await R2DirectUploader.shared.uploadProcessedPhoto(processed)
                        editAttachments.append(att)
                        AudioFeedback.shared.playShutter()
                    } catch {}
                }
                isUploading = false
            }
        }
    }
}

/// macOS 标题栏窗口拖拽手势区域（配合 .hiddenTitleBar 实现全区域平滑拖拽）
fileprivate struct WindowDragHandleView: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }
    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

fileprivate final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

