import XCTest
@testable import LooseLeaf

/// MAC-3 / MAC-8：检索派生（一次计算 + 上限）与条目/账目版本号解耦。
final class GlobalSearchPresentationTests: XCTestCase {

    private func entry(_ id: Int, title: String = "咖啡手记", content: String = "") -> LifeEntry {
        LifeEntry(
            id: id,
            title: title,
            content: content,
            occurredAt: "2026-10-01T10:00:00+08:00"
        )
    }

    private func corpus(_ entries: [LifeEntry]) -> [SearchableLifeEntry] {
        entries.map { entry in
            SearchableLifeEntry(
                entry: entry,
                haystack: [entry.title, entry.content, entry.location ?? "", entry.cityName ?? ""]
                    .joined(separator: "\n")
                    .lowercased()
            )
        }
    }

    /// 本地命中超过 200 条时必须截断并给出「共命中 N 条」提示。
    func test01_LocalResultsAreCappedAt200WithMoreHint() {
        let entries = (1...500).map { entry($0, title: "咖啡 第 \($0) 则") }
        let presentation = SearchPresentation.make(
            query: "咖啡",
            corpus: corpus(entries),
            remote: nil
        )

        XCTAssertEqual(presentation.localMatchCount, 500)
        XCTAssertTrue(presentation.localTruncated)
        let entryHits = presentation.sections.first(where: { $0.id == "section-entries" })?.hits ?? []
        XCTAssertEqual(entryHits.count, SearchPresentation.localLimit)
        XCTAssertEqual(presentation.allHits.count, SearchPresentation.localLimit)
        XCTAssertTrue(
            presentation.sections.first?.title.contains("200 / 500") == true,
            "分组标题必须同时给出展示数与真实命中数"
        )
    }

    /// 远端结果不得重复本地已命中的 id；本地未展示的命中也要参与去重。
    func test02_RemoteResultsAreDedupedAgainstAllLocalMatches() {
        let local = (1...3).map { entry($0, title: "咖啡 \($0)") }
        let remote = GlobalSearchResponse(
            query: "咖啡",
            entries: [entry(2, title: "咖啡 2"), entry(9, title: "咖啡 9")],
            footprints: [],
            wishes: [],
            projects: []
        )
        let presentation = SearchPresentation.make(
            query: "咖啡",
            corpus: corpus(local),
            remote: remote
        )
        let ids = presentation.allHits.compactMap { hit -> Int? in
            if case .entry(let e) = hit { return e.id }
            return nil
        }
        XCTAssertEqual(ids, [1, 2, 3, 9], "远端 id=2 已被本地命中，不得重复出现")
    }

    /// 同一个 key 连续求值只计算一次；query 变化才重新计算。
    func test03_MemoComputesOncePerKey() {
        let entries = (1...20).map { entry($0) }
        let searchCorpus = corpus(entries)
        var memo = SearchPresentationMemo()
        let key = SearchPresentationMemo.Key(query: "咖啡", entriesRevision: 7, remoteVersion: 3)

        let first = memo.presentation(key: key, corpus: searchCorpus, remote: nil)
        let second = memo.presentation(key: key, corpus: searchCorpus, remote: nil)

        XCTAssertEqual(memo.computeCount, 1, "同样的 query + 数据版本只允许派生一次")
        XCTAssertEqual(first.localMatchCount, second.localMatchCount)
        XCTAssertEqual(first.allHits.count, 20)

        let another = SearchPresentationMemo.Key(query: "茶", entriesRevision: 7, remoteVersion: 3)
        _ = memo.presentation(key: another, corpus: searchCorpus, remote: nil)
        XCTAssertEqual(memo.computeCount, 2, "query 变化必须重新派生")
    }

    /// 远端结果属于上一个关键词时必须被忽略，不能挂在新结果下面。
    func test05_StaleRemoteResponseIsIgnored() {
        let local = [entry(1, title: "茶席手记")]
        let staleRemote = GlobalSearchResponse(
            query: "咖啡",
            entries: [],
            footprints: [],
            wishes: [Wish(id: 1, title: "咖啡机")],
            projects: []
        )
        let presentation = SearchPresentation.make(
            query: "茶",
            corpus: corpus(local),
            remote: staleRemote
        )
        XCTAssertTrue(presentation.sections.allSatisfy { $0.id != "section-wishes" },
                      "上一关键词的心愿命中不得出现在新关键词下")
        XCTAssertEqual(presentation.allHits.count, 1)
    }

    /// MAC-8：仅账目变化时，生活视角的 streamRows key 保持不变；账目视角才失效。
    func test04_TransactionRevisionDoesNotInvalidateLifeStreamRowsKey() {
        let before = AppState.streamRowsCacheKey(
            entriesRevision: 10,
            transactionsRevision: 3,
            category: .daily,
            searchQuery: ""
        )
        let afterTransactionOnly = AppState.streamRowsCacheKey(
            entriesRevision: 10,
            transactionsRevision: 4,
            category: .daily,
            searchQuery: ""
        )
        XCTAssertEqual(before, afterTransactionOnly)

        let entryChanged = AppState.streamRowsCacheKey(
            entriesRevision: 11,
            transactionsRevision: 4,
            category: .daily,
            searchQuery: ""
        )
        XCTAssertNotEqual(afterTransactionOnly, entryChanged, "条目变化必须让时间流失效")

        let ledgerBefore = AppState.streamRowsCacheKey(
            entriesRevision: 10,
            transactionsRevision: 3,
            category: .transaction,
            searchQuery: ""
        )
        let ledgerAfter = AppState.streamRowsCacheKey(
            entriesRevision: 10,
            transactionsRevision: 4,
            category: .transaction,
            searchQuery: ""
        )
        XCTAssertNotEqual(ledgerBefore, ledgerAfter, "账目视角必须随账目版本失效")

        let filterBefore = AppState.filteredEntriesCacheKey(
            entriesRevision: 10,
            transactionsRevision: 3,
            category: .daily,
            searchQuery: "咖啡"
        )
        XCTAssertNotEqual(entryChanged, filterBefore)
    }
}
