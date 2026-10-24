// GlobalSearchPresentation.swift
// 全局检索的纯派生层
//
// 背景：`GlobalSearchModalView` 原先用多个 computed property 在 body 里反复
// 遍历全部条目（`localEntryMatches` → `mergedEntries` → `flatSections` →
// `allHits`），一次 body 求值就可能扫 4 遍 N 条；结果区还是非 Lazy 的 VStack。
//
// 这里把检索结果一次性派生为不可变值 `SearchPresentation`：
// - body 只读，不再触发任何 O(N) 扫描；
// - 本地命中上限 200 条，并给出「仅显示前 N 条」提示；
// - 每个条目的可搜索串在 `AppState.searchableEntries` 里预计算并记忆化。

import SwiftUI

/// 预计算可搜索串的条目
struct SearchableLifeEntry: Sendable {
    let entry: LifeEntry
    /// 已 lowercased 的「标题 + 正文 + 地点 + 城市」
    let haystack: String
}

/// 扁平化检索命中：供 ↑/↓/Return 键盘导航与 ForEach 复用
enum SearchResultHit: Identifiable {
    case entry(LifeEntry)
    case footprint(Footprint)
    case wish(Wish)
    case project(Project)

    var id: String { scrollId }

    var scrollId: String {
        switch self {
        case .entry(let e): return "hit-e-\(e.id)"
        case .footprint(let f): return "hit-f-\(f.id)"
        case .wish(let w): return "hit-w-\(w.id)"
        case .project(let p): return "hit-p-\(p.id)"
        }
    }
}

/// 检索结果分组（稳定 id，避免用数组索引做 ForEach 标识）
struct SearchSection: Identifiable {
    let id: String
    let title: String
    let icon: String
    let tint: Color
    let hits: [SearchResultHit]
}

/// 一次检索的完整展示快照
struct SearchPresentation {
    /// 本地命中上限：超过后只展示前 200 条，并提示细化关键词
    static let localLimit = 200

    var sections: [SearchSection] = []
    var allHits: [SearchResultHit] = []
    /// 本地实际命中总数（可能大于展示数）
    var localMatchCount: Int = 0
    /// 是否因上限截断了本地结果
    var localTruncated: Bool = false

    var hasResults: Bool { !sections.isEmpty }

    static let empty = SearchPresentation()

    static func make(
        query: String,
        corpus: [SearchableLifeEntry],
        remote: GlobalSearchResponse?
    ) -> SearchPresentation {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return .empty }

        // 远端结果是按输入去抖异步返回的：新关键词刚输入、旧请求还没回来时，
        // appState.globalSearchResult 仍属于上一个关键词。直接采用会让「茶」
        // 下面短暂挂着「咖啡」的足迹/心愿/造物命中 —— 只认 query 与当前输入一致的结果。
        let remote = remote.flatMap { response in
            response.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == q
                ? response
                : nil
        }

        var presentation = SearchPresentation()
        var localHits: [LifeEntry] = []
        localHits.reserveCapacity(min(corpus.count, Self.localLimit))
        var seen = Set<Int>()
        var matchedCount = 0

        for item in corpus {
            guard item.haystack.contains(q) else { continue }
            matchedCount += 1
            // 即使超出展示上限也继续记录 id，避免远端结果把「本地已命中但未展示」的条目再补一遍。
            seen.insert(item.entry.id)
            if localHits.count < Self.localLimit {
                localHits.append(item.entry)
            }
        }

        var mergedEntries = localHits
        var remoteEntries: [LifeEntry] = []
        if let remote {
            remoteEntries.reserveCapacity(remote.entries.count)
            for entry in remote.entries where !seen.contains(entry.id) {
                seen.insert(entry.id)
                remoteEntries.append(entry)
            }
            mergedEntries.append(contentsOf: remoteEntries)
        }

        presentation.localMatchCount = matchedCount
        presentation.localTruncated = matchedCount > localHits.count

        if !mergedEntries.isEmpty {
            let title = presentation.localTruncated
                ? "生活印记 (\(localHits.count) / \(matchedCount))"
                : "生活印记 (\(mergedEntries.count))"
            presentation.sections.append(SearchSection(
                id: "section-entries",
                title: title,
                icon: "book.pages",
                tint: ArchivePalette.inkMuted,
                hits: mergedEntries.map { .entry($0) }
            ))
        }
        if let remote, !remote.footprints.isEmpty {
            presentation.sections.append(SearchSection(
                id: "section-footprints",
                title: "山川足迹 (\(remote.footprints.count))",
                icon: "map",
                tint: ArchivePalette.accentWarm,
                hits: remote.footprints.map { .footprint($0) }
            ))
        }
        if let remote, !remote.wishes.isEmpty {
            presentation.sections.append(SearchSection(
                id: "section-wishes",
                title: "心愿清单 (\(remote.wishes.count))",
                icon: "sparkles",
                tint: ArchivePalette.accentWarm,
                hits: remote.wishes.map { .wish($0) }
            ))
        }
        if let remote, !remote.projects.isEmpty {
            presentation.sections.append(SearchSection(
                id: "section-projects",
                title: "造物项目 (\(remote.projects.count))",
                icon: "hammer",
                tint: ArchivePalette.accentMoss,
                hits: remote.projects.map { .project($0) }
            ))
        }

        presentation.allHits = presentation.sections.flatMap(\.hits)
        return presentation
    }
}

/// 检索派生记忆器：同样的 key（query + 数据版本 + 远端结果版本）只计算一次。
struct SearchPresentationMemo {
    struct Key: Equatable {
        var query: String
        var entriesRevision: Int
        var remoteVersion: Int

        init(query: String, entriesRevision: Int, remoteVersion: Int) {
            self.query = query
            self.entriesRevision = entriesRevision
            self.remoteVersion = remoteVersion
        }
    }

    private var key: Key?
    private var cached: SearchPresentation?
    private(set) var computeCount = 0

    mutating func presentation(
        key newKey: Key,
        corpus: [SearchableLifeEntry],
        remote: GlobalSearchResponse?
    ) -> SearchPresentation {
        if let key, key == newKey, let cached {
            return cached
        }
        let computed = SearchPresentation.make(query: newKey.query, corpus: corpus, remote: remote)
        key = newKey
        cached = computed
        computeCount += 1
        return computed
    }
}
