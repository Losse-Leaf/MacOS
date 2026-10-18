import Foundation

/// 统一分页拉取助手。
/// 集中页大小、最大页数保险丝与终止条件，避免 AppState / 导出器各自维护一份
/// 略有差异的翻页循环（此前存在三份拷贝，其中一份还是死代码）。
enum Pagination {
    /// 单次同步最多翻多少页，防止后端 total 异常导致死循环
    static let maxPages = 200

    static func fetchAllEntries(
        since: String?,
        pageSize: Int = 100,
        useETagOnFirstPage: Bool = false
    ) async throws -> [LifeEntry] {
        var page = 1
        var all: [LifeEntry] = []
        while page <= maxPages {
            let response = try await APIClient.shared.fetchEntries(
                page: page,
                pageSize: pageSize,
                since: since,
                useETag: useETagOnFirstPage && page == 1
            )
            all.append(contentsOf: response.entries)
            if response.entries.count < pageSize || all.count >= response.total {
                break
            }
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
        while batchIndex < maxPages {
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
        while page <= maxPages {
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
