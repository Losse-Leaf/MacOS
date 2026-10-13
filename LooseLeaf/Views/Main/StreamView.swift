import SwiftUI

/// 桌面主窗口工作台与时间流视图 (StreamView)
/// 严格遵循 docs/macos.md §6 & §7 与 docs/web.md §2.5 规范：
/// 1. 叠加纸张微噪点与系统 Vibrancy 半透明材质
/// 2. 集成 52 周生活刻度热力图、四维分类过滤、#标签下钻与即时模糊搜索
/// 3. 相邻记录跨度 >= 14 天自动渲染「岁月留白刻度切线」
/// 4. 胶片相纸以 .film-frame 装裱呈现，点击进入暗房大图灯箱
public struct StreamView: View {
    @Bindable var appState: AppState

    @State private var showComposeSheet: Bool = false
    @State private var composeType: EntryType = .life
    @State private var composeTitle: String = ""
    @State private var composeContent: String = ""
    @State private var composeLocation: String = ""
    @State private var composeFeatured: Bool = false

    // 行内速写卡片状态 (Inline Quick Composer)
    @State private var quickType: EntryType = .life
    @State private var quickTitle: String = ""
    @State private var quickContent: String = ""
    @State private var quickLocation: String = ""
    @State private var quickFeatured: Bool = false

    // 管理模式：编辑与删除状态
    @State private var editingEntry: LifeEntry?
    @State private var entryToDelete: LifeEntry?
    @State private var showDeleteConfirm: Bool = false

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
                }
            }

            // 暗房全屏看图灯箱
            if let att = appState.lightboxAttachment {
                editorialLightboxOverlay(attachment: att)
            }
        }
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        .sheet(isPresented: $showComposeSheet) {
            composeNewEntrySheet
        }
        .sheet(item: $editingEntry) { entry in
            editEntrySheet(entry: entry)
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
            .padding(.top, 18)

            Divider().overlay(ArchivePalette.borderSubtle)

            // 导航菜单项
            VStack(alignment: .leading, spacing: 4) {
                ForEach(WorkbenchSection.allCases) { section in
                    let selected = appState.activeSection == section
                    Button {
                        appState.activeSection = section
                        AudioFeedback.shared.playPaperFlip()
                    } label: {
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
                                .fill(selected ? ArchivePalette.archiveSubtle : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(selected ? ArchivePalette.borderDivider : Color.clear, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
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
                        .fill(ArchivePalette.accentMoss)
                        .frame(width: 6, height: 6)
                    Text("主理人管理级别")
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Spacer()
                    Text(appState.globalHotkeyLabel)
                        .font(ArchiveTypography.monoScale(size: 10))
                        .foregroundStyle(ArchivePalette.inkMuted)
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

                    // 即时模糊搜索框
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        TextField("检索散页标题、正文或城市…", text: $appState.searchQuery)
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.bodySans(size: 12))
                            .frame(width: 175)
                        if !appState.searchQuery.isEmpty {
                            Button {
                                appState.searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            .buttonStyle(.plain)
                        }
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
                        Task {
                            await appState.refreshAll(forceFull: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .keyboardShortcut("r", modifiers: [.command])
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

                // 3. GitHub 风格 52 周生活刻度热力图
                LifeActivityHeatmapView(entries: appState.entries, weeksCount: 38)

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
                        }
                    }
                }
            }
            .padding(24)
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
                Button {
                    toggleFeatured(entry)
                } label: {
                    Image(systemName: entry.featured == true ? "star.fill" : "star")
                        .font(.system(size: 11.5))
                        .foregroundStyle(entry.featured == true ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                }
                .buttonStyle(.plain)
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

            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
            }

            Text(entry.content)
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
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
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
            }

            TextEditor(text: $composeContent)
                .font(ArchiveTypography.bodySans(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 150)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

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
                    Task {
                        let req = CreateEntryRequest(
                            type: composeType.rawValue,
                            title: composeTitle,
                            content: composeContent,
                            occurredAt: FormatUtils.beijingISOString(),
                            location: finalLoc,
                            featured: composeFeatured,
                            cityCode: resolvedCode,
                            cityName: finalLoc
                        )
                        _ = try? await SyncManager.shared.submitEntry(req)
                        AudioFeedback.shared.playShutter()
                        composeTitle = ""
                        composeContent = ""
                        composeLocation = ""
                        composeFeatured = false
                        showComposeSheet = false
                        await appState.loadConfigAndProfile()
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(composeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 500)
        .background(ArchivePalette.archivePaper)
    }

    // MARK: - 行内速写卡片与管理动作 (Inline Quick Composer & Management)

    private var inlineQuickComposerCard: some View {
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

            HStack {
                TextField(
                    appState.profile.displayCity.isEmpty ? "地点（如：杭州，自动点亮行迹）" : appState.profile.displayCity,
                    text: $quickLocation
                )
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 11.5))
                .padding(6)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(maxWidth: 240)

                Spacer()

                Button("落墨归档 (⌘↩)") {
                    submitInlineQuickEntry()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(quickContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func submitInlineQuickEntry() {
        let content = quickContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let location = quickLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCode = FormatUtils.resolveCityCode(from: location)
        let finalLoc = location.isEmpty ? (appState.profile.displayCity.isEmpty ? nil : appState.profile.displayCity) : location
        Task {
            let req = CreateEntryRequest(
                type: quickType.rawValue,
                title: quickTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content,
                occurredAt: FormatUtils.beijingISOString(),
                location: finalLoc,
                featured: quickFeatured,
                cityCode: resolvedCode,
                cityName: finalLoc
            )
            _ = try? await SyncManager.shared.submitEntry(req)
            AudioFeedback.shared.playShutter()
            quickTitle = ""
            quickContent = ""
            quickLocation = ""
            quickFeatured = false
            await appState.loadConfigAndProfile()
        }
    }

    private func toggleFeatured(_ entry: LifeEntry) {
        guard entry.id > 0 else { return }
        let newFeatured = !(entry.featured ?? false)
        Task {
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
        Task {
            _ = try? await APIClient.shared.deleteEntry(id: entry.id)
            AudioFeedback.shared.playPaperFlip()
            await appState.loadEntries(forceFull: true)
            await appState.loadConfigAndProfile()
            if appState.highlightedEntry?.id == entry.id {
                appState.highlightedEntry = nil
            }
        }
    }

    private func editEntrySheet(entry: LifeEntry) -> some View {
        EditEntrySheetView(entry: entry) { updated in
            Task {
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(entryTypeBadge(entry.type))
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Text(entry.parsedDate.dotDateTime)
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer()
                if appState.isPaired && entry.id > 0 {
                    Button("删除记录") {
                        Task {
                            try? await APIClient.shared.deleteEntry(id: entry.id)
                            await appState.loadEntries(forceFull: true)
                            appState.highlightedEntry = nil
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .buttonStyle(.plain)
                }
                Button("关闭") {
                    appState.highlightedEntry = nil
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
            }

            ScrollView {
                Text(entry.content)
                    .font(ArchiveTypography.bodySans(size: 14))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 160, maxHeight: 340)
        }
        .padding(24)
        .frame(width: 520)
        .background(ArchivePalette.archivePaper)
    }

    // MARK: - 暗房全屏看图灯箱 (EditorialLightbox)

    private func editorialLightboxOverlay(attachment: Attachment) -> some View {
        ZStack {
            ArchivePalette.inkPrimary.opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.lightboxAttachment = nil
                }

            VStack(spacing: 16) {
                if let url = APIClient.shared.resolveMediaURL(attachment.url) {
                    FilmFrameView(
                        imageURL: url,
                        caption: attachment.originalFilename,
                        metaText: (attachment.width != nil && attachment.height != nil)
                            ? "\(attachment.width!) × \(attachment.height!) px"
                            : nil,
                        maxHeight: 540
                    )
                    .frame(maxWidth: 780)
                }

                Button("关闭灯箱 ESC") {
                    appState.lightboxAttachment = nil
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .keyboardShortcut(.cancelAction)
            }
            .padding(32)
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

