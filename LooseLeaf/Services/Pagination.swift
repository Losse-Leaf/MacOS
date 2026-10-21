import Foundation

/// 统一分页拉取助手。
/// 集中页大小、最大页数保险丝与终止条件，避免 AppState / 导出器各自维护一份
/// 略有差异的翻页循环（此前存在三份拷贝，其中一份还是死代码）。
enum Pagination {
    /// 单次同步最多翻多少页，防止后端 total 异常导致死循环
    static let maxPages = 200
    /// 单次同步最多拉多少条记录（防止后端返回异常时把整机内存吃光）
    static let maxEntries = 50_000
    static let maxTransactions = 20_000

    /// 分页拉取生活档案。
    /// - Parameter onFirstPage: 第一页到达时的回调（用于让 UI 立即渲染首屏内容，
    ///   而不必等待全部页拉完）。原实现要等所有页拉完才返回，
    ///   1,000 条档案时用户会盯着空白等待。
    static func fetchAllEntries(
        since: String?,
        pageSize: Int = 100,
        useETagOnFirstPage: Bool = false,
        onFirstPage: (@Sendable (Int, [LifeEntry]) async -> Void)? = nil
    ) async throws -> [LifeEntry] {
        var page = 1
        var all: [LifeEntry] = []
        all.reserveCapacity(pageSize)
        while page <= maxPages {
            // 取消检查：用户切页 / 退出时必须能停下，而不是继续跑完 200 页
            try Task.checkCancellation()
            let response = try await APIClient.shared.fetchEntries(
                page: page,
                pageSize: pageSize,
                since: since,
                useETag: useETagOnFirstPage && page == 1
            )
            all.append(contentsOf: response.entries)
            if page == 1 {
                await onFirstPage?(response.total, response.entries)
            }
            if response.entries.count < pageSize || all.count >= response.total {
                break
            }
            if all.count >= maxEntries { break }
            page += 1
        }
        return all
    }

    static func fetchAllTransactions(
        since: String?,
        batchLimit: Int = 500,
        useETagOnFirstBatch: Bool = false
    ) async throws -> [Transaction] {
        var offset = 0
        var batchIndex = 0
        var all: [Transaction] = []
        all.reserveCapacity(batchLimit)
        while batchIndex < maxPages {
            try Task.checkCancellation()
            let batch = try await APIClient.shared.fetchTransactions(
                since: since,
                limit: batchLimit,
                offset: offset,
                useETag: useETagOnFirstBatch && batchIndex == 0
            )
            all.append(contentsOf: batch)
            if batch.count < batchLimit {
                break
            }
            offset += batch.count
            batchIndex += 1
            if all.count >= maxTransactions { break }
        }
        return all
    }

    static func fetchAllWishes(
        pageSize: Int = 100,
        kind: String? = nil,
        status: String? = nil
    ) async throws -> [Wish] {
        var page = 1
        var all: [Wish] = []
        all.reserveCapacity(pageSize)
        while page <= maxPages {
            try Task.checkCancellation()
            let response = try await APIClient.shared.fetchWishes(
                page: page,
                pageSize: pageSize,
                kind: kind,
                status: status
            )
            all.append(contentsOf: response.wishes)
            if response.wishes.count < pageSize || all.count >= response.total {
                break
            }
            page += 1
        }
        return all
    }
}
