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

    @State private var showComposeSheet: Bool = false
    @State private var composeType: EntryType = .life
    @State private var composeTitle: String = ""
    @State private var composeContent: String = ""
    @State private var composeLocation: String = ""
    @State private var composeFeatured: Bool = false
    @State private var composeOccurredAt: Date = Date()
    @State private var composeAttachments: [Attachment] = []
    @State private var isComposeUploading: Bool = false
    @State private var composeUploadProgress: Double = 0.0
    @State private var isComposeDragTargeted: Bool = false
    @State private var composeExtractedCameraLine: String = ""

    // 行内速写卡片状态 (Inline Quick Composer)
    @State private var isQuickComposerExpanded: Bool = false
    @State private var quickType: EntryType = .life
    @State private var quickTitle: String = ""
    @State private var quickContent: String = ""
    @State private var quickLocation: String = ""
    @State private var quickFeatured: Bool = false
    @State private var quickOccurredAt: Date = Date()
    @State private var quickAttachments: [Attachment] = []
    @State private var quickExtractedCameraLine: String = ""
    @State private var isQuickUploading: Bool = false
    @State private var isQuickDragTargeted: Bool = false

    // 键盘流与检索状态
    @State private var keyboardScrollPosition: Int?
    @State private var localSearchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var isOnThisDayExpanded: Bool = true

    // 管理模式：编辑与删除状态
    @State private var editingEntry: LifeEntry?
    @State private var entryToDelete: LifeEntry?
    @State private var showDeleteConfirm: Bool = false
    @State private var editingTransaction: Transaction?
    @State private var txToDelete: Transaction?
    @State private var showDeleteTxConfirm: Bool = false

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
                    if let update = UpdateChecker.shared.availableUpdate {
                        updateAvailableStrip(update: update)
                    }
                    if let banner = appState.statusBanner {
                        topNoticeStrip(text: banner, isError: false)
                    } else if let err = appState.errorBanner {
                        topNoticeStrip(text: err, isError: true)
                    }

                    Group {
                        switch appState.activeSection {
                        case .stream:
                            streamTimelineCanvas
                        case .darkroom:
                            DarkroomDropZone(appState: appState)
                        case .ledger:
                            LedgerAssetsView(appState: appState)
                        case .creations:
                            ProjectsWishesView(appState: appState)
                        case .dossier:
                            CuratorDossierView(appState: appState)
                        case .settings:
                            SettingsView(appState: appState)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(nil, value: appState.activeSection)
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
        }
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        .sheet(isPresented: $showComposeSheet) {
            composeNewEntrySheet
        }
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
        .confirmationDialog(
            "确认删除该条生活手稿？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除手稿", role: .destructive) {
                if let target = entryToDelete {
                    deleteEntryAction(target)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后记录将从时间流中移除，关联的附件与下渗足迹将一并清理。")
        }
        .confirmationDialog(
            "确认删除该笔流水账目？",
            isPresented: $showDeleteTxConfirm,
            titleVisibility: .visible
        ) {
            Button("删除账目", role: .destructive) {
                if let target = txToDelete {
                    deleteTransactionAction(target)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将从本地账本与中枢中移除，月度收支与资产大盘将即刻重新核算。")
        }
        .task {
            await appState.refreshAll()
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

            // 导航菜单项
            VStack(alignment: .leading, spacing: 4) {
                ForEach(WorkbenchSection.allCases) { section in
                    WorkbenchNavRow(
                        section: section,
                        selected: appState.activeSection == section
                    ) {
                        var transaction = SwiftUI.Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            appState.activeSection = section
                        }
                        AudioFeedback.shared.playPaperFlip()
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // 底部全局指标小卡片
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    metricMiniItem(label: "散页", value: "\(max(appState.stats.totalEntries, appState.entries.count))")
                    Spacer()
                    metricMiniItem(label: "底片", value: "\(appState.stats.totalPhotos)")
                    Spacer()
                    metricMiniItem(label: "造物", value: "\(max(appState.stats.totalProjects, appState.projects.count))")
                }

                Divider().overlay(ArchivePalette.borderSubtle)

                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isOnline ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .frame(width: 6, height: 6)
                    Text(appState.isOnline ? (appState.isFlushingOutbox ? "正在同步…" : "已连接数据中枢") : "离线工作态 · 发件箱守护")
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(appState.isOnline ? ArchivePalette.inkMuted : ArchivePalette.accentWarm)
                    Spacer()
                    if !appState.outboxItems.isEmpty {
                        Text("\(appState.outboxItems.count) 待发")
                            .font(ArchiveTypography.monoScale(size: 10, weight: .semibold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    } else {
                        Text(appState.globalHotkeyLabel)
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
            }
            .padding(12)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )
            .padding(12)
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
                // 1. 顶部引言与工具栏
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("生活档案与时光手账")
                            .font(ArchiveTypography.editorialSerif(size: 21, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        if !appState.profile.motto.isEmpty {
                            Text(appState.profile.motto)
                                .font(ArchiveTypography.editorialSerif(size: 13))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                        }
                    }

                    Spacer()

                    // 即时模糊搜索框（带 180ms 防抖，⌘F 自动聚焦与宽度弹性展开）
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11.5))
                            .foregroundStyle(isSearchFocused ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                        TextField("检索散页标题、正文或城市… (⌘F)", text: $localSearchText)
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.bodySans(size: 12))
                            .focused($isSearchFocused)
                            .frame(width: isSearchFocused ? 240 : 180)
                            .animation(.easeOut(duration: 0.16), value: isSearchFocused)
                            .onChange(of: localSearchText) { _, newVal in
                                if newVal.isEmpty {
                                    appState.searchQuery = ""
                                }
                            }
                            .task(id: localSearchText) {
                                guard !localSearchText.isEmpty else { return }
                                do {
                                    try await Task.sleep(nanoseconds: 180_000_000)
                                    appState.searchQuery = localSearchText
                                } catch {}
                            }
                        if !localSearchText.isEmpty {
                            Button {
                                localSearchText = ""
                                appState.searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清除搜索")
                        }
                    }
                    .background(
                        Button("") {
                            isSearchFocused = true
                        }
                        .keyboardShortcut("f", modifiers: [.command])
                        .opacity(0)
                        .allowsHitTesting(false)
                    )
                    .onAppear {
                        localSearchText = appState.searchQuery
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                    )

                    Button {
                        exportMarkdown()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .accessibilityLabel("导出当前视图为 Markdown")
                    .help("导出当前视图为 Markdown")

                    Button {
                        Task { @MainActor in
                            await appState.refreshAll(forceFull: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .accessibilityLabel("同步最新档案")
                    .help("同步最新档案 (⌘R)")

                    Button {
                        showComposeSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.pencil")
                            Text("撰写散页")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    .keyboardShortcut("n", modifiers: [.command])
                }

                // 2. 顶部行内即时手稿速写卡片 (Inline Quick Composer)
                inlineQuickComposerCard

                if !appState.onThisDayEntries.isEmpty {
                    onThisDayBannerCard
                }

                // 3. GitHub 风格 52 周生活刻度热力图
                LifeActivityHeatmapView(
                    entryCounts: appState.entryCountsByDate,
                    totalCount: appState.entries.count,
                    weeksCount: 38
                )

                // 4. 四维母体分类切换栏与 #标签 筛选
                HStack(spacing: 6) {
                    ForEach(ArchiveCategory.allCases) { cat in
                        if cat != .transaction || appState.isPaired {
                            PaperPillButton(
                                title: cat.label,
                                isSelected: appState.selectedCategory == cat
                            ) {
                                appState.selectedCategory = cat
                                AudioFeedback.shared.playPaperFlip()
                            }
                        }
                    }

                    if let tag = appState.selectedHashtag {
                        PaperPillButton(title: "#\(tag) ×", isSelected: true) {
                            appState.selectedHashtag = nil
                        }
                    }

                    Spacer()
                }

                if !appState.allHashtags.isEmpty && appState.selectedHashtag == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(appState.allHashtags.prefix(10), id: \.tag) { item in
                                Button {
                                    appState.selectedHashtag = item.tag
                                    AudioFeedback.shared.playTink()
                                } label: {
                                    Text("#\(item.tag) (\(item.count))")
                                        .font(ArchiveTypography.monoScale(size: 10.5))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(ArchivePalette.archiveSubtle)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
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
                            entryCardView(entry)
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

    // MARK: - 单条散页卡片渲染

    private func entryCardView(_ entry: LifeEntry) -> some View {
        let parsed = entry.parsedDate
        return VStack(alignment: .leading, spacing: 10) {
            // 顶栏：形态印章 + 北京时间戳 + 地点 + 管理操作
            HStack(spacing: 8) {
                Text(entryTypeBadge(entry.type))
                    .font(ArchiveTypography.monoScale(size: 10.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Text(parsed.dotDateTime)
                    .font(ArchiveTypography.monoScale(size: 11.5))
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
                        .font(ArchiveTypography.monoScale(size: 10))
                        .foregroundStyle(ArchivePalette.accentMoss)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(ArchivePalette.accentMoss, lineWidth: 0.5)
                        )
                }

                if (entry.syncStatus ?? "synced") != "synced" {
                    Text("待同步")
                        .font(ArchiveTypography.monoScale(size: 10))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                Spacer()

                // 管理级别专属操作按钮
                if entry.type == "transaction" {
                    Button("编辑") {
                        if let tx = appState.transactions.first(where: { $0.id == entry.id }) {
                            editingTransaction = tx
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .buttonStyle(.plain)

                    Button("删除") {
                        if let tx = appState.transactions.first(where: { $0.id == entry.id }) {
                            txToDelete = tx
                            showDeleteTxConfirm = true
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .buttonStyle(.plain)

                    Button("详情") {
                        appState.highlightedEntry = entry
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .buttonStyle(.plain)
                } else {
                    Button {
                        toggleFeatured(entry)
                    } label: {
                        Image(systemName: entry.featured == true ? "star.fill" : "star")
                            .font(.system(size: 11.5))
                            .foregroundStyle(entry.featured == true ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.featured == true ? "取消精选" : "设为精选")
                    .help(entry.featured == true ? "取消精选" : "设为精选")

                    Button("编辑") {
                        editingEntry = entry
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .buttonStyle(.plain)

                    Button("删除") {
                        entryToDelete = entry
                        showDeleteConfirm = true
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .buttonStyle(.plain)

                    Button("详情") {
                        appState.highlightedEntry = entry
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .buttonStyle(.plain)
                }
            }

            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
            }

            Text(LocalizedStringKey(entry.content))
                .font(ArchiveTypography.bodySans(size: 13.5))
                .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.92))
                .lineSpacing(4)
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
                                    AudioFeedback.shared.playPaperFlip()
                                }
                                .frame(width: 280)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }

            // #标签 列表
            let tags = entry.hashtags
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            appState.selectedHashtag = tag
                            AudioFeedback.shared.playTink()
                        } label: {
                            Text("#\(tag)")
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    appState.keyboardFocusedEntryId == entry.id ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle,
                    lineWidth: appState.keyboardFocusedEntryId == entry.id ? 1.0 : 0.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            appState.highlightedEntry = entry
            AudioFeedback.shared.playPaperFlip()
        }
        .contextMenu {
            if entry.type == "transaction" {
                if let tx = appState.transactions.first(where: { $0.id == entry.id }) {
                    Button {
                        editingTransaction = tx
                    } label: {
                        Label("编辑账目", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        txToDelete = tx
                        showDeleteTxConfirm = true
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
                    appState.highlightedEntry = entry
                    AudioFeedback.shared.playPaperFlip()
                } label: {
                    Label("查看手稿详情", systemImage: "book.pages")
                }
                Button {
                    toggleFeatured(entry)
                } label: {
                    Label(entry.featured == true ? "取消精选印记" : "标记为精选印记", systemImage: entry.featured == true ? "star.slash" : "star")
                }
                Button {
                    editingEntry = entry
                } label: {
                    Label("编辑手稿", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    entryToDelete = entry
                    showDeleteConfirm = true
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
                    NSPasteboard.general.setString(entry.parsedDate.dotDateTime, forType: .string)
                    AudioFeedback.shared.playTink()
                    appState.showTemporaryBanner("已拷贝时间戳至剪贴板")
                } label: {
                    Label("拷贝时间戳", systemImage: "clock")
                }
            }
        }
        .paperHover()
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
            Text("随时按下 ⌘ + ⇧ + L 呼出极速闪念窗，或点击右上角「撰写散页」记录真实可感的当下。")
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

    // MARK: - 撰写新散页与详情弹窗

    private var composeNewEntrySheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("撰写新散页记录")
                .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 6) {
                ForEach(EntryType.allCases) { kind in
                    PaperPillButton(
                        title: kind.label,
                        icon: kind.symbolName,
                        isSelected: composeType == kind
                    ) {
                        composeType = kind
                    }
                }
            }

            TextField("标题（可选）", text: $composeTitle)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.editorialSerif(size: 14))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 8) {
                TextField(
                    appState.profile.displayCity.isEmpty ? "所处地点（如：杭州，自动点亮行迹）" : appState.profile.displayCity,
                    text: $composeLocation
                )
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 12))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                PaperDateTimePicker(selection: $composeOccurredAt, label: nil)
            }

            TextEditor(text: $composeContent)
                .font(ArchiveTypography.bodySans(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 130)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // 附带相纸底片槽位 (可点击选择相片、拖拽照片进入、或 ⌘V 粘贴图片)
            VStack(alignment: .leading, spacing: 6) {
                if !composeAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(composeAttachments) { att in
                                HStack(spacing: 5) {
                                    if let url = APIClient.shared.resolveMediaURL(att.url) {
                                        CachedFilmImageView(url: url, maxHeight: 22)
                                            .frame(width: 22, height: 22)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    Text(att.originalFilename)
                                        .font(ArchiveTypography.monoScale(size: 11))
                                        .lineLimit(1)
                                        .frame(maxWidth: 100)
                                    Button {
                                        composeAttachments.removeAll { $0.id == att.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(ArchivePalette.accentWarm)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3.5)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        selectPhotosForCompose()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 11.5))
                            Text(composeAttachments.isEmpty ? "添加相纸照片…" : "继续添加…")
                                .font(ArchiveTypography.bodySans(size: 11.5))
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                    Button {
                        pastePhotoForCompose()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11.5))
                            Text("粘贴剪贴板截图")
                                .font(ArchiveTypography.bodySans(size: 11.5))
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                    if isComposeUploading {
                        ProgressView()
                            .controlSize(.small)
                        Text("上传底片中 (\(Int(composeUploadProgress * 100))%)…")
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    } else if !composeExtractedCameraLine.isEmpty {
                        Text(composeExtractedCameraLine)
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.accentMoss)
                            .lineLimit(1)
                    }

                    Spacer()

                    if !composeAttachments.isEmpty {
                        Text("已装裱 \(composeAttachments.count) 张底片")
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.accentMoss)
                    }
                }
            }
            .padding(10)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        isComposeDragTargeted ? ArchivePalette.accentWarm : ArchivePalette.borderDivider,
                        style: StrokeStyle(lineWidth: isComposeDragTargeted ? 1.2 : 0.5, dash: [4, 3])
                    )
            )
            .onDrop(of: [.fileURL, .image], isTargeted: $isComposeDragTargeted) { providers in
                handlePhotosDropForCompose(providers)
                return true
            }

            HStack {
                Toggle("标记为精选印记", isOn: $composeFeatured)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .tint(ArchivePalette.accentWarm)

                Spacer()

                Button("取消") { showComposeSheet = false }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                Button("落墨归档 ⌘↩") {
                    let loc = composeLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedCode = FormatUtils.resolveCityCode(from: loc)
                    let finalLoc = loc.isEmpty ? (appState.profile.displayCity.isEmpty ? nil : appState.profile.displayCity) : loc
                    var bodyText = composeContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    if bodyText.isEmpty && !composeAttachments.isEmpty {
                        bodyText = composeExtractedCameraLine.isEmpty ? "散页生活手稿印记" : composeExtractedCameraLine
                    }
                    if !composeExtractedCameraLine.isEmpty && !bodyText.contains(composeExtractedCameraLine) {
                        bodyText += "\n\n> \(composeExtractedCameraLine)"
                    }
                    let contentToSubmit = bodyText
                    let attIds = composeAttachments.map(\.id)
                    Task { @MainActor in
                        let req = CreateEntryRequest(
                            type: composeType.rawValue,
                            title: composeTitle,
                            content: contentToSubmit,
                            occurredAt: FormatUtils.beijingISOString(from: composeOccurredAt),
                            location: finalLoc,
                            featured: composeFeatured,
                            cityCode: resolvedCode,
                            cityName: finalLoc,
                            attachmentIds: attIds
                        )
                        _ = try? await SyncManager.shared.submitEntry(req)
                        AudioFeedback.shared.playShutter()
                        composeTitle = ""
                        composeContent = ""
                        composeLocation = ""
                        composeFeatured = false
                        composeOccurredAt = Date()
                        composeAttachments.removeAll()
                        composeExtractedCameraLine = ""
                        showComposeSheet = false
                        await appState.loadConfigAndProfile()
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled((composeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && composeAttachments.isEmpty) || isComposeUploading)
            }
        }
        .padding(22)
        .frame(width: 500)
        .background(ArchivePalette.archivePaper)
    }

    // MARK: - 那年今日 · 岁月回响折叠横幅
    private var onThisDayBannerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    Text("那年今日 · 岁月回响 (\(appState.onThisDayEntries.count))")
                        .font(ArchiveTypography.editorialSerif(size: 14.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isOnThisDayExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isOnThisDayExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
                .buttonStyle(.plain)
            }

            if isOnThisDayExpanded {
                Divider().overlay(ArchivePalette.accentWarm.opacity(0.3))

                VStack(spacing: 8) {
                    ForEach(appState.onThisDayEntries) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title.isEmpty ? "无题手稿" : entry.title)
                                    .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                if !entry.content.isEmpty {
                                    Text(entry.content)
                                        .font(ArchiveTypography.bodySans(size: 11.5))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(entry.parsedDate.dotDate)
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.inkMuted)
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
        }
        .padding(14)
        .background(ArchivePalette.accentWarm.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.accentWarm.opacity(0.35), lineWidth: 0.8)
        )
    }

    // MARK: - 行内速写卡片与管理动作 (Inline Quick Composer & Management)

    private var inlineQuickComposerCard: some View {
        Group {
            if !isQuickComposerExpanded {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    Text("此刻随笔碎念…")
                        .font(ArchiveTypography.bodySans(size: 12.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isQuickComposerExpanded = true
                        }
                        AudioFeedback.shared.playPaperFlip()
                    } label: {
                        HStack(spacing: 4) {
                            Text("展开速写")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                        }
                        .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isQuickComposerExpanded = true
                    }
                    AudioFeedback.shared.playPaperFlip()
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            ForEach(EntryType.allCases) { kind in
                                PaperPillButton(
                                    title: kind.label,
                                    icon: kind.symbolName,
                                    isSelected: quickType == kind
                                ) {
                                    quickType = kind
                                }
                            }
                        }

                        Spacer()

                        Toggle("精选", isOn: $quickFeatured)
                            .toggleStyle(.checkbox)
                            .font(ArchiveTypography.bodySans(size: 11.5))

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isQuickComposerExpanded = false
                            }
                            AudioFeedback.shared.playPaperFlip()
                        } label: {
                            HStack(spacing: 3) {
                                Text("收起")
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 9))
                            }
                            .font(ArchiveTypography.bodySans(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .help("收起速写卡片")
                    }

                    TextField("标题（选填，留空则为随笔短笺）", text: $quickTitle)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                        .padding(8)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    TextEditor(text: $quickContent)
                        .font(ArchiveTypography.bodySans(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 68, maxHeight: 110)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            Group {
                                if quickContent.isEmpty {
                                    Text("随时在此写下一笔散页手稿或灵感碎念（支持 #标签），按 ⌘↩ 直接归档…")
                                        .font(ArchiveTypography.bodySans(size: 12.5))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 10)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )

                    // 附带相片缩略条
                    if !quickAttachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(quickAttachments) { att in
                                    HStack(spacing: 4) {
                                        if let url = APIClient.shared.resolveMediaURL(att.url) {
                                            CachedFilmImageView(url: url, maxHeight: 18)
                                                .frame(width: 18, height: 18)
                                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                        }
                                        Text(att.originalFilename)
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                            .lineLimit(1)
                                            .frame(maxWidth: 80)
                                        Button {
                                            quickAttachments.removeAll { $0.id == att.id }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2.5)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                    )
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(
                            appState.profile.displayCity.isEmpty ? "地点（如：杭州）" : appState.profile.displayCity,
                            text: $quickLocation
                        )
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .padding(6)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: 160)

                        PaperDateTimePicker(selection: $quickOccurredAt, showQuickShortcuts: false)

                        Button {
                            selectPhotosForQuick()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 11))
                                if !quickAttachments.isEmpty {
                                    Text("\(quickAttachments.count)")
                                        .font(ArchiveTypography.monoScale(size: 10.5))
                                }
                            }
                            .foregroundStyle(quickAttachments.isEmpty ? ArchivePalette.inkSecondary : ArchivePalette.accentMoss)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("添加相纸底片照片…")

                        if isQuickUploading {
                            ProgressView().controlSize(.small)
                        }

                        Spacer()

                        Button("落墨归档 (⌘↩)") {
                            submitInlineQuickEntry()
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled((quickContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && quickAttachments.isEmpty) || isQuickUploading)
                    }
                }
                .padding(14)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
            }
        }
    }

    private func submitInlineQuickEntry() {
        var content = quickContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty && !quickAttachments.isEmpty {
            content = quickExtractedCameraLine.isEmpty ? "散页生活相纸印记" : quickExtractedCameraLine
        }
        guard !content.isEmpty || !quickAttachments.isEmpty else { return }

        if !quickExtractedCameraLine.isEmpty && !content.contains(quickExtractedCameraLine) {
            content += "\n\n> \(quickExtractedCameraLine)"
        }

        let location = quickLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCode = FormatUtils.resolveCityCode(from: location)
        let finalLoc = location.isEmpty ? (appState.profile.displayCity.isEmpty ? nil : appState.profile.displayCity) : location
        let attIds = quickAttachments.map(\.id)
        let contentToSubmit = content

        Task { @MainActor in
            let req = CreateEntryRequest(
                type: quickType.rawValue,
                title: quickTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                content: contentToSubmit,
                occurredAt: FormatUtils.beijingISOString(from: quickOccurredAt),
                location: finalLoc,
                featured: quickFeatured,
                cityCode: resolvedCode,
                cityName: finalLoc,
                attachmentIds: attIds
            )
            _ = try? await SyncManager.shared.submitEntry(req)
            AudioFeedback.shared.playShutter()
            quickTitle = ""
            quickContent = ""
            quickLocation = ""
            quickFeatured = false
            quickOccurredAt = Date()
            quickAttachments.removeAll()
            quickExtractedCameraLine = ""
            withAnimation(.easeInOut(duration: 0.18)) {
                isQuickComposerExpanded = false
            }
            await appState.loadConfigAndProfile()
        }
    }

    // MARK: - 散页撰写与速写相纸直传管线

    private func selectPhotosForCompose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .rawImage]
        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            Task { @MainActor in
                await processAndUploadComposeFiles(urls)
            }
        }
    }

    private func pastePhotoForCompose() {
        guard let rawData = DropLoader.readImageFromPasteboard() else { return }
        Task { @MainActor in
            isComposeUploading = true
            composeUploadProgress = 0.08
            do {
                let name = "pasteboard-\(Int(Date().timeIntervalSince1970)).jpg"
                let processed = try await ImageProcessor.processImageDataInBackground(rawData, originalFilename: name)
                if composeExtractedCameraLine.isEmpty && !processed.exifMetadata.formattedCameraLine.isEmpty {
                    composeExtractedCameraLine = processed.exifMetadata.formattedCameraLine
                }
                let att = try await R2DirectUploader.shared.uploadProcessedPhoto(processed) { prog in
                    Task { @MainActor in self.composeUploadProgress = prog }
                }
                composeAttachments.append(att)
                AudioFeedback.shared.playShutter()
            } catch {}
            isComposeUploading = false
        }
    }

    private func handlePhotosDropForCompose(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        Task { @MainActor in
            let urls = await DropLoader.loadDroppablePhotoURLs(from: providers)
            guard !urls.isEmpty else { return }
            await processAndUploadComposeFiles(urls)
        }
    }

    private func processAndUploadComposeFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isComposeUploading = true
        composeUploadProgress = 0.05
        let total = Double(urls.count)
        var finished = 0.0
        for url in urls {
            do {
                let processed = try await ImageProcessor.processImageFileInBackground(at: url)
                if composeExtractedCameraLine.isEmpty && !processed.exifMetadata.formattedCameraLine.isEmpty {
                    composeExtractedCameraLine = processed.exifMetadata.formattedCameraLine
                }
                let att = try await R2DirectUploader.shared.uploadProcessedPhoto(processed) { prog in
                    Task { @MainActor in self.composeUploadProgress = (finished + prog) / total }
                }
                composeAttachments.append(att)
                AudioFeedback.shared.playShutter()
            } catch {}
            finished += 1
            composeUploadProgress = finished / total
        }
        isComposeUploading = false
    }

    private func selectPhotosForQuick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .rawImage]
        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            Task { @MainActor in
                isQuickUploading = true
                for url in urls {
                    do {
                        let processed = try await ImageProcessor.processImageFileInBackground(at: url)
                        if quickExtractedCameraLine.isEmpty && !processed.exifMetadata.formattedCameraLine.isEmpty {
                            quickExtractedCameraLine = processed.exifMetadata.formattedCameraLine
                        }
                        let att = try await R2DirectUploader.shared.uploadProcessedPhoto(processed)
                        quickAttachments.append(att)
                        AudioFeedback.shared.playShutter()
                    } catch {}
                }
                isQuickUploading = false
            }
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
        let matchingTx = isTx ? appState.transactions.first(where: { $0.id == entry.id }) : nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(entryTypeBadge(entry.type))
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Text(entry.parsedDate.dotDateTime)
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer()
                if appState.isPaired && entry.id > 0 {
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
                                txToDelete = tx
                                showDeleteTxConfirm = true
                            }
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button("删除记录") {
                            Task { @MainActor in
                                try? await APIClient.shared.deleteEntry(id: entry.id)
                                await appState.loadEntries(forceFull: true)
                                appState.highlightedEntry = nil
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
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                ScrollView {
                    Text(LocalizedStringKey(entry.content))
                        .font(ArchiveTypography.bodySans(size: 14))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 160, maxHeight: 340)
            }
        }
        .padding(24)
        .frame(width: 520)
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
    @State private var editLocation: String
    @State private var editFeatured: Bool

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
        _editLocation = State(initialValue: entry.location ?? entry.cityName ?? "")
        _editFeatured = State(initialValue: entry.featured ?? false)
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
                .padding(6)
                .frame(minHeight: 140)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("地点（如：杭州，自动更新行迹关联）", text: $editLocation)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 12))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Toggle("标记为精选印记", isOn: $editFeatured)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .tint(ArchivePalette.accentWarm)

                Spacer()

                Button("取消") {
                    onCancel()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                Button("保存修改 ⌘↩") {
                    let loc = editLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedCode = FormatUtils.resolveCityCode(from: loc)
                    let req = UpdateEntryRequest(
                        type: entry.type,
                        title: editTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        content: editContent.trimmingCharacters(in: .whitespacesAndNewlines),
                        occurredAt: entry.occurredAt,
                        location: loc.isEmpty ? nil : loc,
                        featured: editFeatured,
                        cityCode: resolvedCode,
                        cityName: loc.isEmpty ? nil : loc
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

