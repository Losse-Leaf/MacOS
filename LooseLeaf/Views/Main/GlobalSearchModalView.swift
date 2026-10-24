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
    /// 当前键盘高亮的命中项（用稳定的 scrollId 追踪，而不是数组索引）
    @State private var highlightedHitId: String? = nil
    /// 一次派生、body 只读的检索结果
    @State private var presentation = SearchPresentation.empty
    /// 派生记忆器：同一 key 只计算一次
    @State private var presentationMemo = SearchPresentationMemo()
    /// 检索代号：旧请求结束时不得清掉新请求的 spinner
    @State private var searchGeneration = 0

    private var presentationKey: SearchPresentationMemo.Key {
        SearchPresentationMemo.Key(
            query: debouncedQuery,
            entriesRevision: appState.contentRevision,
            remoteVersion: appState.globalSearchResultVersion
        )
    }

    private func activateHit(_ hit: SearchResultHit) {
        switch hit {
        case .entry(let e): onSelectEntry(e)
        case .footprint(let f): onSelectFootprint(f)
        case .wish(let w): onSelectWish(w)
        case .project(let p): onSelectProject(p)
        }
        onDismiss()
    }

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

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏输入框
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(ArchivePalette.inkMuted)

                TextField("搜索生活档案、山川足迹、心愿与造物…", text: $query)
                    .accessibilityLabel("全局搜索")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.editorialSerif(size: 15))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .focused($isFieldFocused)
                    .onChange(of: query) { _, newQ in
                        handleQueryChange(newQ)
                    }
                    .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
                        let hits = presentation.allHits
                        guard !hits.isEmpty else { return .ignored }
                        let current = highlightedHitId.flatMap { id in hits.firstIndex { $0.scrollId == id } } ?? 0
                        switch press.key {
                        case .upArrow:
                            highlightedHitId = hits[(current - 1 + hits.count) % hits.count].scrollId
                            return .handled
                        case .downArrow:
                            highlightedHitId = hits[(current + 1) % hits.count].scrollId
                            return .handled
                        case .return:
                            activateHit(hits[current])
                            return .handled
                        default:
                            return .ignored
                        }
                    }

                if !query.isEmpty {
                    Button("清空") {
                        query = ""
                        debouncedQuery = ""
                        appState.clearGlobalSearchResult()
                        presentation = .empty
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
                .accessibilityLabel("关闭全局检索")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 内容列表区
            ScrollViewReader { proxy in
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
                    } else if isSearchingRemote && !presentation.hasResults {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在检索全量历史归档…")
                                .font(ArchiveTypography.monoScale(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 50)
                    } else if !presentation.hasResults {
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
                        ForEach(presentation.sections) { section in

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: section.icon)
                                        .font(.system(size: 11))
                                    Text(section.title)
                                        .font(ArchiveTypography.monoScale(size: 11))
                                }
                                .foregroundStyle(section.tint)
                                .padding(.horizontal, 4)

                                // 生活印记为纵向单列；足迹 / 心愿 / 项目保持双列网格。
                                // 结果区改为 Lazy 容器：本地最多 200 条时也不会一次性物化全部卡片。
                                if section.id == "section-entries" {
                                    LazyVStack(spacing: 6) {
                                        ForEach(section.hits) { hit in
                                            searchResultCard(hit, isHighlighted: hit.scrollId == highlightedHitId)
                                                .id(hit.scrollId)
                                        }
                                    }
                                } else {
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                        ForEach(section.hits) { hit in
                                            searchResultCard(hit, isHighlighted: hit.scrollId == highlightedHitId)
                                                .id(hit.scrollId)
                                        }
                                    }
                                }
                            }
                        }

                        if presentation.localTruncated {
                            Text("本地仅展示前 \(SearchPresentation.localLimit) 条，共命中 \(presentation.localMatchCount) 条；请补充关键词以缩小范围。")
                                .font(ArchiveTypography.monoScale(size: 10.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: highlightedHitId) { _, newId in
                guard let newId else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
            }

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 底栏状态说明
            HStack {
                Text("已收录 \(appState.entries.count) 条散页印记")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)

                Spacer()

                HStack(spacing: 12) {
                    if appState.globalSearchLoading.isVisible {
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
        .frame(minWidth: ArchiveSheetWidth.wide * 0.86, idealWidth: ArchiveSheetWidth.wide, maxWidth: ArchiveSheetWidth.wide)
        .frame(minHeight: 420, idealHeight: 500, maxHeight: 640)
        .background(ArchivePalette.archivePaper)
        .onAppear {
            isFieldFocused = true
        }
        // 检索派生只在这里做一次；body 只读 `presentation`。
        .task(id: presentationKey) {
            let key = presentationKey
            let corpus = appState.searchableEntries
            let remote = appState.globalSearchResult
            presentation = presentationMemo.presentation(key: key, corpus: corpus, remote: remote)
        }
    }

    private func handleQueryChange(_ newQ: String) {
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        // 关键词变化后重置键盘高亮（改为按稳定 scrollId 追踪）
        highlightedHitId = nil
        let trimmed = newQ.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncedQuery = ""
            appState.clearGlobalSearchResult()
            presentation = .empty
            isSearchingRemote = false
            return
        }

        debouncedQuery = trimmed
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled, generation == searchGeneration else { return }
            isSearchingRemote = true
            // 关键：改走 AppState 的统一检索入口。
            // 原先弹窗**自己**发请求并直接写 `appState.globalSearchResult` ——
            // 于是绕过了 `globalSearchGeneration` 代号机制：
            // ⌘K 弹窗与顶栏搜索并发时，**旧请求可以覆盖新结果**；
            // 而旧任务无条件把 spinner 置 false，会让新请求还在飞时指示器提前消失。
            await appState.performGlobalSearch(query: trimmed)
            guard generation == searchGeneration else { return }
            isSearchingRemote = false
        }
    }

    // MARK: - 子卡片组件

    @ViewBuilder
    private func searchResultCard(_ hit: SearchResultHit, isHighlighted: Bool) -> some View {
        switch hit {
        case .entry(let entry):
            entryResultCard(entry, isHighlighted: isHighlighted)
        case .footprint(let fp):
            footprintResultCard(fp, isHighlighted: isHighlighted)
        case .wish(let wish):
            wishResultCard(wish, isHighlighted: isHighlighted)
        case .project(let proj):
            projectResultCard(proj, isHighlighted: isHighlighted)
        }
    }

    private func entryResultCard(_ entry: LifeEntry, isHighlighted: Bool) -> some View {
        Button {
            onSelectEntry(entry)
            onDismiss()
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

                    Text(FormatUtils.formatDate(entry.occurredAt))
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
                    .stroke(isHighlighted ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: isHighlighted ? 1.2 : 0.5)
            )
            .background(isHighlighted ? ArchivePalette.accentWarm.opacity(0.06) : Color.clear)
            .paperHover()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footprintResultCard(_ fp: Footprint, isHighlighted: Bool) -> some View {
        Button {
            onSelectFootprint(fp)
            onDismiss()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    let titleStr = (fp.title?.isEmpty == false) ? fp.title! : "旅程漫游"
                    Text("\(fp.cityName) · \(titleStr)")
                        .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(FormatUtils.formatDate(fp.visitedAt))
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
                    .stroke(isHighlighted ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: isHighlighted ? 1.2 : 0.5)
            )
            .paperHover()
        }
        .buttonStyle(.plain)
    }

    private func wishResultCard(_ wish: Wish, isHighlighted: Bool) -> some View {
        Button {
            onSelectWish(wish)
            onDismiss()
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
                    .stroke(isHighlighted ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: isHighlighted ? 1.2 : 0.5)
            )
            .paperHover()
        }
        .buttonStyle(.plain)
    }

    private func projectResultCard(_ proj: Project, isHighlighted: Bool) -> some View {
        Button {
            onSelectProject(proj)
            onDismiss()
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
                    .stroke(isHighlighted ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: isHighlighted ? 1.2 : 0.5)
            )
            .paperHover()
        }
        .buttonStyle(.plain)
    }
}
