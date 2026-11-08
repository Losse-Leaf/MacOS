import XCTest
@testable import LooseLeaf

/// 同步一致性复核的 macOS 回归测试：
/// - CREATE 返回 410 Gone 时丢弃本地乐观行与发件箱项（账目还要回滚汇总）；
/// - DELETE 返回 404 时视为目标已不存在，消费事件并删除本地行；
/// - 增量账目分页只按非墓碑行推进 offset。
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

    func test05_ActiveTransactionCountIgnoresPurgeTombstones() {
        let batch = [
            transaction(1),
            transaction(2).withDeletedAt("2026-11-08T10:00:00+08:00"),
            transaction(3),
            transaction(4).withDeletedAt("2026-11-08T11:00:00+08:00")
        ]

        XCTAssertEqual(
            Pagination.activeTransactionCount(batch),
            2,
            "墓碑不占服务端 offset，不能算进分页推进"
        )
        XCTAssertEqual(
            Pagination.activeTransactionCount([transaction(1).withDeletedAt("2026-11-08T10:00:00+08:00")]),
            0
        )
        XCTAssertEqual(
            Pagination.activeTransactionCount([transaction(1).withDeletedAt("")]),
            1,
            "空字符串 deleted_at 是活跃行"
        )
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
}

private extension Transaction {
    func withDeletedAt(_ value: String?) -> Transaction {
        var copy = self
        copy.deletedAt = value
        return copy
    }
}
