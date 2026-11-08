import XCTest
@testable import LooseLeaf

/// 同步一致性复核的 macOS 回归测试：
/// - CREATE 返回 410 Gone 时丢弃本地乐观行与发件箱项（账目还要回滚汇总）；
/// - DELETE 返回 404 时视为目标已不存在，消费事件并删除本地行；
/// - 增量账目分页按服务端原始页大小推进 offset（真实软删行也占 offset）。
/// - 升级后一次性清空账目游标，强制全量补拉旧版可能漏掉的记录。
@MainActor
final class SyncGoneAndPaginationTests: XCTestCase {

    private var tempDir: URL!
    private var savedSnapshot: LocalArchiveSnapshot!
    private var hadOverride: URL?

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("looseleaf-sync-gone-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        hadOverride = SyncManager.snapshotFileURLOverride
        SyncManager.snapshotFileURLOverride = tempDir.appendingPathComponent("snapshot.json")
        savedSnapshot = SyncManager.shared.currentSnapshot()
    }

    override func tearDown() async throws {
        SyncManager.snapshotFileURLOverride = hadOverride
        if let savedSnapshot {
            SyncManager.shared.saveSnapshot(savedSnapshot)
        }
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func entry(_ id: Int, syncStatus: String = "pending_create") -> LifeEntry {
        LifeEntry(
            id: id,
            title: "待同步散页 \(id)",
            content: "内容",
            occurredAt: "2026-11-08T10:00:00+08:00",
            syncStatus: syncStatus
        )
    }

    private func transaction(_ id: Int, amount: Int64 = 4250) -> Transaction {
        Transaction(
            id: id,
            amount: amount,
            type: "expense",
            category: "餐饮",
            title: "待同步账目 \(id)",
            occurredAt: String(
                format: "%04d-%02d-15T10:00:00+08:00",
                FormatUtils.beijingCurrentYearMonth().year,
                FormatUtils.beijingCurrentYearMonth().month
            ),
            syncStatus: "pending_create"
        )
    }

    private func summary(expense: Int64) -> TransactionSummary {
        var s = TransactionSummary()
        s.totalExpense = expense
        s.balance = -expense
        if expense > 0 {
            s.categoryBreakdown["餐饮"] = expense
        }
        return s
    }

    // MARK: - 410 Gone

    func test01_DiscardGoneEntryRemovesLocalRowAndOutbox() {
        let tempId = -501
        let item = OutboxItem(kind: .createEntry, localTempId: tempId)
        SyncManager.shared.saveSnapshot(
            LocalArchiveSnapshot(entries: [entry(tempId)], outbox: [item])
        )

        SyncManager.shared.discardGoneEntry(tempId: tempId)

        let latest = SyncManager.shared.currentSnapshot()
        XCTAssertFalse(latest.entries.contains { $0.id == tempId }, "410 后本地乐观散页必须删除")
        XCTAssertFalse(latest.outbox.contains { $0.id == item.id }, "410 后 CREATE 事件必须消费掉")
    }

    func test02_DiscardGoneTransactionRemovesLocalRowAndRollsBackSummary() {
        let tempId = -502
        let item = OutboxItem(kind: .createTransaction, localTempId: tempId)
        SyncManager.shared.saveSnapshot(
            LocalArchiveSnapshot(
                transactions: [transaction(tempId)],
                transactionSummary: summary(expense: 4250),
                outbox: [item]
            )
        )

        SyncManager.shared.discardGoneTransaction(tempId: tempId)

        let latest = SyncManager.shared.currentSnapshot()
        XCTAssertFalse(latest.transactions.contains { $0.id == tempId }, "410 后本地乐观账目必须删除")
        XCTAssertFalse(latest.outbox.contains { $0.id == item.id }, "410 后 CREATE 事件必须消费掉")
        XCTAssertEqual(latest.transactionSummary.totalExpense, 0, "410 后必须回滚乐观汇总")
        XCTAssertEqual(latest.transactionSummary.balance, 0)
    }

    // MARK: - DELETE 404

    func test03_DiscardGoneDeleteEntryConsumesEvent() {
        let serverId = 601
        let item = OutboxItem(kind: .deleteEntry, localTempId: serverId, targetServerId: serverId)
        SyncManager.shared.saveSnapshot(
            LocalArchiveSnapshot(entries: [entry(serverId, syncStatus: "synced")], outbox: [item])
        )

        SyncManager.shared.discardGoneDelete(item: item)

        let latest = SyncManager.shared.currentSnapshot()
        XCTAssertFalse(latest.entries.contains { $0.id == serverId }, "服务端已 404，本地行必须删除")
        XCTAssertFalse(latest.outbox.contains { $0.id == item.id }, "404 视为删除成功，事件必须消费")
    }

    func test04_DiscardGoneDeleteTransactionRollsBackSummary() {
        let serverId = 602
        let item = OutboxItem(
            kind: .deleteTransaction,
            localTempId: serverId,
            targetServerId: serverId
        )
        SyncManager.shared.saveSnapshot(
            LocalArchiveSnapshot(
                transactions: [transaction(serverId)],
                transactionSummary: summary(expense: 4250),
                outbox: [item]
            )
        )

        SyncManager.shared.discardGoneDelete(item: item)

        let latest = SyncManager.shared.currentSnapshot()
        XCTAssertFalse(latest.transactions.contains { $0.id == serverId })
        XCTAssertFalse(latest.outbox.contains { $0.id == item.id })
        XCTAssertEqual(latest.transactionSummary.totalExpense, 0, "404 删除也要回滚汇总")
    }

    // MARK: - 增量分页 offset

    func test05_NextTransactionOffsetUsesRawBatchSize() {
        // 500 条里包含真实软删行：旧实现只数活跃行，会误判末页。
        XCTAssertEqual(
            Pagination.nextTransactionOffset(currentOffset: 0, batchSize: 500, batchLimit: 500),
            500
        )
        XCTAssertEqual(
            Pagination.nextTransactionOffset(currentOffset: 500, batchSize: 500, batchLimit: 500),
            1000
        )
        // 500 真实行 + 10 条 purge 墓碑：服务端 offset 只前进了 500。
        XCTAssertEqual(
            Pagination.nextTransactionOffset(currentOffset: 0, batchSize: 510, batchLimit: 500),
            500
        )
        // 495 真实行 + 10 条墓碑：批次 505 看似满页，实际已到末页；
        // 按 500 推进最多多一次空页请求，不会跳过真实行。
        XCTAssertEqual(
            Pagination.nextTransactionOffset(currentOffset: 0, batchSize: 505, batchLimit: 500),
            500
        )
        XCTAssertNil(Pagination.nextTransactionOffset(currentOffset: 0, batchSize: 499, batchLimit: 500))
        XCTAssertNil(Pagination.nextTransactionOffset(currentOffset: 0, batchSize: 0, batchLimit: 500))
    }

    func test06_MergedTransactionsRemovesPurgeTombstone() {
        let local = [transaction(7, amount: 9900)]
        let tombstone = transaction(7, amount: 0).withDeletedAt("2026-11-08T12:00:00+08:00")

        let merged = SyncManager.mergedTransactions(
            current: local,
            incoming: [tombstone],
            isDelta: true
        )

        XCTAssertTrue(merged.isEmpty, "purge 墓碑必须让本地账目消失，而不是留下幽灵行")
    }

    // MARK: - 一次性游标重置

    func test07_LedgerPaginationFixResetRunsOnce() {
        let suiteName = "looseleaf-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("无法创建测试 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SyncManager.shared.saveSnapshot(
            LocalArchiveSnapshot(
                transactions: [transaction(1)],
                lastTransactionsSyncCursor: "2026-11-08T10:00:00Z"
            )
        )

        SyncManager.shared.resetLedgerCursorForPaginationFixIfNeeded(defaults: defaults)
        XCTAssertNil(
            SyncManager.shared.currentSnapshot().lastTransactionsSyncCursor,
            "升级后首次注水必须清空账目游标，强制全量补拉"
        )

        SyncManager.shared.saveSnapshot(
            LocalArchiveSnapshot(
                transactions: [transaction(1)],
                lastTransactionsSyncCursor: "2026-11-08T11:00:00Z"
            )
        )
        SyncManager.shared.resetLedgerCursorForPaginationFixIfNeeded(defaults: defaults)
        XCTAssertEqual(
            SyncManager.shared.currentSnapshot().lastTransactionsSyncCursor,
            "2026-11-08T11:00:00Z",
            "一次性重置不能每轮都清空游标"
        )
    }
}

private extension Transaction {
    func withDeletedAt(_ value: String?) -> Transaction {
        var copy = self
        copy.deletedAt = value
        return copy
    }
}
