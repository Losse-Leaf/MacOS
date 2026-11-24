import SwiftUI

/// 全局聚光灯档案检索模态框 (GlobalSearchModalView)
/// 严格 1:1 对标 Web 端 `web/src/components/SearchModal.vue` (⌘K Spotlight)
/// 融合本地 120ms 防抖即时检索与服务端 220ms 跨年历史归档检索 (生活手稿 / 心愿清单)
@MainActor
public struct GlobalSearchModalView: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void
    var onSelectEntry: (LifeEntry) -> Void
    var onSelectWish: (Wish) -> Void

    @State private var query: String = ""
    @State private var debouncedQuery: String = ""
    @State private var isSearchingRemote: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var isFieldFocused: Bool
    @State private var highlightedHitId: String? = nil
    @State private var presentation = SearchPresentation.empty
    @State private var presentationMemo = SearchPresentationMemo()
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
        case .wish(let w): onSelectWish(w)
        }
        onDismiss()
    }

    public init(
        appState: AppState,
        onDismiss: @escaping () -> Void,
        onSelectEntry: @escaping (LifeEntry) -> Void,
        onSelectWish: @escaping (Wish) -> Void
    ) {
        self.appState = appState
        self.onDismiss = onDismiss
        self.onSelectEntry = onSelectEntry
        self.onSelectWish = onSelectWish
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏输入框
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(ArchivePalette.inkMuted)

                TextField("搜索生活档案与心愿清单…", text: $query)
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
                        switch press.key {
                        case .upArrow:
                            if let currentId = highlightedHitId, let current = hits.firstIndex(where: { $0.scrollId == currentId }) {
                                highlightedHitId = hits[(current - 1 + hits.count) % hits.count].scrollId
                            } else {
                                highlightedHitId = hits.last?.scrollId
                            }
                            return .handled
                        case .downArrow:
                            if let currentId = highlightedHitId, let current = hits.firstIndex(where: { $0.scrollId == currentId }) {
                                highlightedHitId = hits[(current + 1) % hits.count].scrollId
                            } else {
                                highlightedHitId = hits.first?.scrollId
                            }
                            return .handled
                        case .return:
                            let target = highlightedHitId.flatMap { id in hits.first(where: { $0.scrollId == id }) } ?? hits.first
                            if let target {
                                activateHit(target)
                            }
                            return .handled
                        default:
                            return .ignored
                        }
                    }

                if !query.isEmpty {
                    Button("清空") {
                        searchTask?.cancel()
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
                    .paperButtonFocusRing(cornerRadius: 3)
                }

                PaperIconButton(
                    systemName: ArchiveIcon.close.systemName,
                    label: "关闭全局检索",
                    help: "关闭全局检索 (ESC)",
                    size: 12,
                    tint: ArchivePalette.inkMuted
                ) {
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 内容列表区
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        let trimmedRaw = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedRaw.isEmpty {
                            VStack(spacing: 6) {
                                Text("输入关键词开始检索全库档案")
                                    .font(ArchiveTypography.bodySans(size: 13, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                Text("支持跨年份检索生活记录与心愿清单")
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else if (debouncedQuery != trimmedRaw || isSearchingRemote) && !presentation.hasResults {
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
                    Text("↑↓ 选择 · ↵ 打开 · ESC 关闭")
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
        .task(id: presentationKey) {
            let key = presentationKey
            let corpus = appState.searchableEntries
            let remote = appState.globalSearchResult
            let pres = presentationMemo.presentation(key: key, corpus: corpus, remote: remote)
            presentation = pres
            if highlightedHitId == nil, let first = pres.allHits.first {
                highlightedHitId = first.scrollId
            }
        }
    }

    private func handleQueryChange(_ newQ: String) {
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        highlightedHitId = nil
        let trimmed = newQ.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncedQuery = ""
            appState.clearGlobalSearchResult()
            presentation = .empty
            isSearchingRemote = false
            return
        }

        // 关键修复：先等 120ms 再更新 debouncedQuery（消除快速连打拼音时每键 0ms 全库扫描），
        // 再等 100ms（合计 220ms）后发起远端跨年检索。
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, generation == searchGeneration else { return }
            debouncedQuery = trimmed

            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, generation == searchGeneration else { return }
            isSearchingRemote = true
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
        case .wish(let wish):
            wishResultCard(wish, isHighlighted: isHighlighted)
        }
    }

    private func entryResultCard(_ entry: LifeEntry, isHighlighted: Bool) -> some View {
        let badgeText = entry.displayBadgeLabel
        let firstContentLine = entry.content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let headline = entry.hasDistinctTitle ? entry.title : (firstContentLine.isEmpty ? "无题记事" : firstContentLine)
        return Button {
            onSelectEntry(entry)
            onDismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("[\(badgeText)]")
                        .font(ArchiveTypography.monoScale(size: 10, weight: .semibold))
                        .foregroundStyle(entry.displayAccentColor)

                    Text(headline)
                        .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)

                    if entry.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .accessibilityLabel("私密散页")
                    }

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

                let loc = entry.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        .paperButtonFocusRing(cornerRadius: 6)
    }

    private func wishResultCard(_ wish: Wish, isHighlighted: Bool) -> some View {
        Button {
            onSelectWish(wish)
            onDismiss()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(wish.title)
                        .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                    if wish.isPrivate == true {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .accessibilityLabel("私密心愿")
                    }
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
        .paperButtonFocusRing(cornerRadius: 6)
    }
}
