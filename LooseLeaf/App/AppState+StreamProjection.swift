import Foundation

// MARK: - 时间流投影、派生索引、跨模块搜索与键盘聚焦

extension AppState {
    /// 时间流行模型：条目 + 与上一条的自然日间隔（用于 14 天留白切线）
    public struct StreamRow: Identifiable, Sendable {
        public let entry: LifeEntry
        public let gapDays: Int
        /// 分组键（YYYY-MM-DD）：同一天的记录归到同一个分组标题下
        public let dayKey: String
        /// 紧凑时间戳（同一分钟折叠、同一天 HH:mm、跨天同年 M月D日、跨年 YYYY年M月D日）
        public let timeLabel: String
        public var id: Int { entry.id }
    }

    /// 仅供检索/测试：条目集合版本号
    public var contentRevision: Int { entriesRevision }

    public func requestStreamSearchFocus() {
        navigation.requestStreamSearchFocus()
    }

    /// 全局检索语料：每个条目预先拼好「标题 + 正文 + 地点 + 城市」的小写串，按 entriesRevision 记忆化。
    var searchableEntries: [SearchableLifeEntry] {
        if let memo = searchCorpusMemo, memo.0 == entriesRevision {
            return memo.1
        }
        let corpus = entries.map { entry in
            SearchableLifeEntry(
                entry: entry,
                haystack: [
                    entry.title,
                    entry.content,
                    entry.location ?? "",
                    entry.cityName ?? ""
                ].joined(separator: "\n").lowercased()
            )
        }
        searchCorpusMemo = (entriesRevision, corpus)
        return corpus
    }

    /// 供主窗口展示的过滤后时间流列表（融合账目视角、分类过滤与模糊搜索）
    public var filteredStreamEntries: [LifeEntry] {
        let key = Self.filteredEntriesCacheKey(
            entriesRevision: entriesRevision,
            transactionsRevision: transactionsRevision,
            category: selectedCategory,
            searchQuery: searchQuery,
            privacyFilter: navigation.streamPrivacyFilter
        )
        if let memo = filteredMemo, memo.key == key {
            return memo.value
        }
        let computed = computeFilteredStreamEntries()
        filteredMemo = (key, computed)
        return computed
    }

    /// 过滤缓存键（纯函数，便于单测）
    nonisolated static func filteredEntriesCacheKey(
        entriesRevision: Int,
        transactionsRevision: Int,
        category: ArchiveCategory,
        searchQuery: String,
        privacyFilter: StreamPrivacyFilter = .all
    ) -> String {
        let txPart = category == .transaction ? String(transactionsRevision) : "0"
        return "\(entriesRevision)|\(txPart)|\(category.rawValue)|\(searchQuery)|\(privacyFilter.rawValue)"
    }

    private func computeFilteredStreamEntries() -> [LifeEntry] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let privacy = navigation.streamPrivacyFilter

        if selectedCategory == .transaction {
            if privacy == .privateOnly { return [] }
            var source = transactions.map { $0.toLifeEntry() }
            if !q.isEmpty {
                source = source.filter { entry in
                    entry.title.lowercased().contains(q)
                    || entry.content.lowercased().contains(q)
                    || (entry.location?.lowercased().contains(q) ?? false)
                    || (entry.cityName?.lowercased().contains(q) ?? false)
                }
            }
            return source
        }

        if !q.isEmpty {
            return searchableEntries.compactMap { item in
                let entry = item.entry
                guard entry.matches(category: selectedCategory) else { return nil }
                if privacy == .privateOnly && !entry.isPrivate { return nil }
                return item.haystack.contains(q) ? entry : nil
            }
        }

        return entries.filter { entry in
            guard entry.matches(category: selectedCategory) else { return false }
            if privacy == .privateOnly && !entry.isPrivate { return false }
            return true
        }
    }

    /// 紧凑时间戳文案
    nonisolated static func compactTimeLabel(
        _ current: FormatUtils.ParsedBeijingDate,
        previous: FormatUtils.ParsedBeijingDate?
    ) -> String {
        guard current.isValid else { return "" }
        guard let previous, previous.isValid else {
            if current.year.count >= 4 {
                return "\(Int(current.month) ?? 0)月\(Int(current.day) ?? 0)日"
            }
            return current.time
        }
        if current.dateKey == previous.dateKey {
            if current.time == previous.time { return "" }
            return current.time
        }
        if current.year == previous.year {
            return "\(Int(current.month) ?? 0)月\(Int(current.day) ?? 0)日"
        }
        return "\(current.year)年\(Int(current.month) ?? 0)月\(Int(current.day) ?? 0)日"
    }

    /// 账目 id → 账目 的索引（按 transactionsRevision 记忆化）
    public var transactionById: [Int: Transaction] {
        if let memo = transactionIndexMemo, memo.0 == transactionsRevision {
            return memo.1
        }
        var map: [Int: Transaction] = [:]
        map.reserveCapacity(transactions.count)
        for tx in transactions { map[tx.id] = tx }
        transactionIndexMemo = (transactionsRevision, map)
        return map
    }

    /// 已算好间隔的时间流（带记忆缓存）
    public var streamRows: [StreamRow] {
        let key = Self.streamRowsCacheKey(
            entriesRevision: entriesRevision,
            transactionsRevision: transactionsRevision,
            category: selectedCategory,
            searchQuery: searchQuery,
            privacyFilter: navigation.streamPrivacyFilter
        )
        if let memo = streamRowsMemo, memo.key == key {
            return memo.value
        }
        ArchivePerformance.mark(.render, "streamRows.recompute")
        let list = filteredStreamEntries
        let rows = Self.buildStreamRows(for: list)
        streamRowsMemo = (key, rows)
        return rows
    }

    /// 为指定条目列表构建时间流显示行（计算紧凑时间标签与 >= 14 天年轮留白）
    public static func buildStreamRows(for list: [LifeEntry]) -> [StreamRow] {
        var rows: [StreamRow] = []
        rows.reserveCapacity(list.count)
        var previousParsed: FormatUtils.ParsedBeijingDate?
        var previousValidDate: Date?
        for entry in list {
            let parsed = entry.parsedDate
            let gap: Int
            if parsed.isValid, let previousValidDate {
                gap = FormatUtils.daysBetween(previousValidDate, parsed.date)
            } else {
                gap = 0
            }
            let label = Self.compactTimeLabel(parsed, previous: previousParsed)
            rows.append(StreamRow(entry: entry, gapDays: gap, dayKey: parsed.dateKey, timeLabel: label))
            previousParsed = parsed
            previousValidDate = parsed.isValid ? parsed.date : nil
        }
        return rows
    }

    /// 时间流缓存键（纯函数，便于单测）
    nonisolated static func streamRowsCacheKey(
        entriesRevision: Int,
        transactionsRevision: Int,
        category: ArchiveCategory,
        searchQuery: String,
        privacyFilter: StreamPrivacyFilter = .all
    ) -> String {
        let txPart = category == .transaction ? String(transactionsRevision) : "0"
        return "\(entriesRevision)|\(txPart)|\(category.rawValue)|\(searchQuery)|\(privacyFilter.rawValue)"
    }

    /// 全库跨模块网络搜索（当已配对时发起，支持足迹、心愿与造物项目联动检索）
    public func performGlobalSearch(query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, isPaired else {
            clearGlobalSearchResult()
            return
        }
        globalSearchGeneration &+= 1
        let generation = globalSearchGeneration
        self.isGlobalSearching = true
        globalSearchLoading.begin()
        defer {
            if generation == globalSearchGeneration {
                self.isGlobalSearching = false
            }
            globalSearchLoading.end()
        }
        do {
            let res = try await APIClient.shared.searchGlobalArchive(query: q, limit: 30)
            guard generation == globalSearchGeneration, !Task.isCancelled else { return }
            self.globalSearchResult = res
            self.globalSearchResultVersion &+= 1
        } catch {
            // 网络受阻或离线时保持本地纯粹搜索
        }
    }

    /// 清空全局检索结果（同时作废在途请求）
    public func clearGlobalSearchResult() {
        globalSearchGeneration &+= 1
        if globalSearchResult != nil {
            globalSearchResult = nil
        }
        globalSearchResultVersion &+= 1
        isGlobalSearching = false
    }

    /// 按北京时间自然日聚合的记录密度（52 周热力图数据源，带记忆缓存）
    public var entryCountsByDate: [String: Int] {
        let key = "\(entriesRevision)"
        if let memo = entryCountsMemo, memo.key == key {
            return memo.value
        }
        var counts: [String: Int] = [:]
        for entry in entries {
            let parsed = entry.parsedDate
            guard parsed.isValid else { continue }
            counts[parsed.dateKey, default: 0] += 1
        }
        entryCountsMemo = (key, counts)
        return counts
    }

    /// 按日期分组的散页索引（记忆化）
    public var entriesByDateKey: [String: [LifeEntry]] {
        let key = "\(entriesRevision)"
        if let memo = entriesByDateMemo, memo.key == key {
            return memo.value
        }
        var grouped: [String: [LifeEntry]] = [:]
        for entry in entries {
            let parsed = entry.parsedDate
            guard parsed.isValid else { continue }
            grouped[parsed.dateKey, default: []].append(entry)
        }
        entriesByDateMemo = (key, grouped)
        return grouped
    }

    // MARK: - 键盘流导航（⌘↑ / ⌘↓ / ⌘↩）

    /// 在筛选后的时间流中上下移动键盘焦点（首次按下正向选首条，反向选末条）
    public func moveSelection(by delta: Int) {
        let list = filteredStreamEntries
        guard !list.isEmpty else { return }
        let targetIndex: Int
        if let currentId = keyboardFocusedEntryId,
           let currentIndex = list.firstIndex(where: { $0.id == currentId }) {
            targetIndex = min(max(currentIndex + delta, 0), list.count - 1)
        } else {
            targetIndex = delta >= 0 ? 0 : list.count - 1
        }
        keyboardFocusedEntryId = list[targetIndex].id
    }

    /// 打开当前键盘聚焦的散页详情（支持「账目」等合成条目视角）
    public func openKeyboardFocusedEntry() {
        guard let id = keyboardFocusedEntryId,
              let entry = filteredStreamEntries.first(where: { $0.id == id })
                ?? entries.first(where: { $0.id == id }) else { return }
        highlightedEntry = entry
    }
}
