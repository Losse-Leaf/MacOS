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
    @State private var composeCityCode: String = ""
    @State private var composeFeatured: Bool = false

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
        .sheet(item: $appState.highlightedEntry) { entry in
            entryDetailSheet(entry: entry)
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
                        .fill(appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .frame(width: 6, height: 6)
                    Text(appState.isPaired ? "钥匙串已授信" : "公开只读视角")
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

                // 2. GitHub 风格 52 周生活刻度热力图
                LifeActivityHeatmapView(entries: appState.entries, weeksCount: 38)

                // 3. 四维母体分类切换栏与 #标签 筛选
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

                // 4. 纵向时间流条目列表 (含 >= 14 天岁月留白切线)
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
            // 顶栏：形态印章 + 北京时间戳 + 地点 + 操作
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

                Button {
                    appState.highlightedEntry = entry
                } label: {
                    Text("详情")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
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
                    appState.profile.displayCity.isEmpty ? "所处地点（如：杭州 · 深夜书房）" : appState.profile.displayCity,
                    text: $composeLocation
                )
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 12))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                TextField("6位城市代码（可选，如 330100 自动下渗足迹）", text: $composeCityCode)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: 11.5))
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
                    Task {
                        let req = CreateEntryRequest(
                            type: composeType.rawValue,
                            title: composeTitle,
                            content: composeContent,
                            occurredAt: FormatUtils.beijingISOString(),
                            location: composeLocation.isEmpty ? (appState.profile.displayCity.isEmpty ? nil : appState.profile.displayCity) : composeLocation,
                            featured: composeFeatured,
                            cityCode: composeCityCode.isEmpty ? nil : composeCityCode,
                            cityName: composeLocation.isEmpty ? nil : composeLocation
                        )
                        _ = try? await SyncManager.shared.submitEntry(req)
                        AudioFeedback.shared.playShutter()
                        composeTitle = ""
                        composeContent = ""
                        composeLocation = ""
                        composeCityCode = ""
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
