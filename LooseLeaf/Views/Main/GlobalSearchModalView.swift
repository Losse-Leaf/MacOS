import SwiftUI

/// 全局聚光灯档案检索模态框 (GlobalSearchModalView)
/// 严格 1:1 对标 Web 端 `web/src/components/SearchModal.vue` (⌘K Spotlight)
/// 融合本地即时检索与服务端全库历史归档检索 (生活手稿 / 山川足迹 / 心愿清单 / 造物项目)
@MainActor
public struct GlobalSearchModalView: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void
    var onSelectEntry: (LifeEntry) -> Void
    var onSelectFootprint: (Footprint) -> Void
    var onSelectWish: (Wish) -> Void
    var onSelectProject: (Project) -> Void

    @State private var query: String = ""
    @State private var debouncedQuery: String = ""
    @State private var isSearchingRemote: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var isFieldFocused: Bool

    public init(
        appState: AppState,
        onDismiss: @escaping () -> Void,
        onSelectEntry: @escaping (LifeEntry) -> Void,
        onSelectFootprint: @escaping (Footprint) -> Void,
        onSelectWish: @escaping (Wish) -> Void,
        onSelectProject: @escaping (Project) -> Void
    ) {
        self.appState = appState
        self.onDismiss = onDismiss
        self.onSelectEntry = onSelectEntry
        self.onSelectFootprint = onSelectFootprint
        self.onSelectWish = onSelectWish
        self.onSelectProject = onSelectProject
    }

    private var localEntryMatches: [LifeEntry] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return appState.entries.filter { entry in
            entry.title.lowercased().contains(q) ||
            entry.content.lowercased().contains(q) ||
            (entry.location?.lowercased().contains(q) ?? false) ||
            (entry.cityName?.lowercased().contains(q) ?? false)
        }
    }

    private var mergedEntries: [LifeEntry] {
        var seen = Set<Int>()
        var list: [LifeEntry] = []
        for item in localEntryMatches {
            seen.insert(item.id)
            list.append(item)
        }
        if let remote = appState.globalSearchResult?.entries {
            for item in remote {
                if !seen.contains(item.id) {
                    seen.insert(item.id)
                    list.append(item)
                }
            }
        }
        return list
    }

    private var remoteFootprints: [Footprint] {
        appState.globalSearchResult?.footprints ?? []
    }

    private var remoteWishes: [Wish] {
        appState.globalSearchResult?.wishes ?? []
    }

    private var remoteProjects: [Project] {
        appState.globalSearchResult?.projects ?? []
    }

    private var hasAnyResults: Bool {
        !mergedEntries.isEmpty ||
        !remoteFootprints.isEmpty ||
        !remoteWishes.isEmpty ||
        !remoteProjects.isEmpty
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏输入框
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(ArchivePalette.inkMuted)

                TextField("搜索生活档案、山川足迹、心愿与造物…", text: $query)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.editorialSerif(size: 15))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .focused($isFieldFocused)
                    .onChange(of: query) { _, newQ in
                        handleQueryChange(newQ)
                    }

                if !query.isEmpty {
                    Button("清空") {
                        query = ""
                        debouncedQuery = ""
                        appState.globalSearchResult = nil
                        isSearchingRemote = false
                    }
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 内容列表区
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(spacing: 6) {
                            Text("输入关键词开始检索全库档案")
                                .font(ArchiveTypography.bodySans(size: 13, weight: .medium))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                            Text("支持跨年份检索生活记录、山川行迹、心愿单与造物手记")
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else if isSearchingRemote && !hasAnyResults {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在检索全量历史归档…")
                                .font(ArchiveTypography.monoScale(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 50)
                    } else if !hasAnyResults {
                        VStack(spacing: 6) {
                            Text("没有找到匹配的生活碎片")
                                .font(ArchiveTypography.bodySans(size: 13, weight: .medium))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                            Text("换个关键词试试，生活总有些未曾命名的瞬间")
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        // 1. 生活印记
                        if !mergedEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "book.pages")
                                        .font(.system(size: 11))
                                    Text("生活印记 (\(mergedEntries.count))")
                                        .font(ArchiveTypography.monoScale(size: 11))
                                }
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(.horizontal, 4)

                                VStack(spacing: 6) {
                                    ForEach(mergedEntries) { entry in
                                        entryResultCard(entry)
                                    }
                                }
                            }
                        }

                        // 2. 山川足迹
                        if !remoteFootprints.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "map")
                                        .font(.system(size: 11))
                                    Text("山川足迹 (\(remoteFootprints.count))")
                                        .font(ArchiveTypography.monoScale(size: 11))
                                }
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(.horizontal, 4)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(remoteFootprints) { fp in
                                        footprintResultCard(fp)
                                    }
                                }
                            }
                        }

                        // 3. 心愿清单
                        if !remoteWishes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11))
                                    Text("心愿清单 (\(remoteWishes.count))")
                                        .font(ArchiveTypography.monoScale(size: 11))
                                }
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(.horizontal, 4)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(remoteWishes) { wish in
                                        wishResultCard(wish)
                                    }
                                }
                            }
                        }

                        // 4. 造物项目
                        if !remoteProjects.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "hammer")
                                        .font(.system(size: 11))
                                    Text("造物项目 (\(remoteProjects.count))")
                                        .font(ArchiveTypography.monoScale(size: 11))
                                }
                                .foregroundStyle(ArchivePalette.accentMoss)
                                .padding(.horizontal, 4)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(remoteProjects) { proj in
                                        projectResultCard(proj)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 底栏状态说明
            HStack {
                Text("已收录 \(appState.entries.count) 条散页印记")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)

                Spacer()

                HStack(spacing: 12) {
                    if isSearchingRemote {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.6)
                            Text("中枢查询中")
                                .font(ArchiveTypography.monoScale(size: 10.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                    }
                    Text("ESC 关闭 · 单击卡片查阅详情")
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(ArchivePalette.archiveSubtle.opacity(0.4))
        }
        .frame(width: 660, height: 500)
        .background(ArchivePalette.archivePaper)
        .onAppear {
            isFieldFocused = true
        }
    }

    private func handleQueryChange(_ newQ: String) {
        searchTask?.cancel()
        let trimmed = newQ.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncedQuery = ""
            appState.globalSearchResult = nil
            isSearchingRemote = false
            return
        }

        debouncedQuery = trimmed
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            isSearchingRemote = true
            defer { isSearchingRemote = false }
            if let res = try? await APIClient.shared.searchGlobalArchive(query: trimmed, limit: 30) {
                guard !Task.isCancelled else { return }
                appState.globalSearchResult = res
            }
        }
    }

    // MARK: - 子卡片组件

    private func entryResultCard(_ entry: LifeEntry) -> some View {
        Button {
            onSelectEntry(entry)
            onDismiss()
            AudioFeedback.shared.playTink()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("[\(entry.type.uppercased())]")
                        .font(ArchiveTypography.monoScale(size: 10, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)

                    Text(entry.title.isEmpty ? "无题记事" : entry.title)
                        .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(entry.occurredAt.prefix(10))
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                if !entry.content.isEmpty {
                    Text(entry.content)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .lineLimit(2)
                }

                let loc = (entry.cityName?.isEmpty == false) ? entry.cityName! : (entry.location ?? "")
                if !loc.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9))
                        Text(loc)
                            .font(ArchiveTypography.monoScale(size: 10))
                    }
                    .foregroundStyle(ArchivePalette.inkMuted)
                }
            }
            .padding(10)
            .background(ArchivePalette.archiveSubtle.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footprintResultCard(_ fp: Footprint) -> some View {
        Button {
            onSelectFootprint(fp)
            onDismiss()
            AudioFeedback.shared.playTink()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    let titleStr = (fp.title?.isEmpty == false) ? fp.title! : "旅程漫游"
                    Text("\(fp.cityName) · \(titleStr)")
                        .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(fp.visitedAt.prefix(10))
                        .font(ArchiveTypography.monoScale(size: 10))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                if let note = fp.note, !note.isEmpty {
                    Text(note)
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(9)
            .background(ArchivePalette.archiveSubtle.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func wishResultCard(_ wish: Wish) -> some View {
        Button {
            onSelectWish(wish)
            onDismiss()
            AudioFeedback.shared.playTink()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(wish.title)
                        .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                    Spacer()
                    if wish.budget > 0 {
                        Text(FormatUtils.formattedYuan(cents: wish.budget, includeSymbol: true))
                            .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }
                if let note = wish.note, !note.isEmpty {
                    Text(note)
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(9)
            .background(ArchivePalette.archiveSubtle.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func projectResultCard(_ proj: Project) -> some View {
        Button {
            onSelectProject(proj)
            onDismiss()
            AudioFeedback.shared.playTink()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(proj.title)
                        .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let st = proj.status, !st.isEmpty {
                        Text(st)
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
                if !proj.description.isEmpty {
                    Text(proj.description)
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(9)
            .background(ArchivePalette.archiveSubtle.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
