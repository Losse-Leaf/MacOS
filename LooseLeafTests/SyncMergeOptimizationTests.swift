import XCTest
@testable import LooseLeaf

/// MAC-4 / MAC-5：后台合并的语义等价性，以及轻量指纹的正确性。
@MainActor
final class SyncMergeOptimizationTests: XCTestCase {

    private func entry(_ id: Int, _ day: Int, updatedAt: String = "2026-10-01T10:00:00+08:00", deletedAt: String? = nil) -> LifeEntry {
        LifeEntry(
            id: id,
            title: "第 \(id) 则手记",
            content: "正文 \(id)",
            occurredAt: String(format: "2026-10-%02dT10:00:00+08:00", day),
            deletedAt: deletedAt,
            updatedAt: updatedAt
        )
    }

    /// 旧实现（同步版）——仅用于对照，排序比较器与生产代码保持一致。
    private func legacyMerged(current: [LifeEntry], incoming: [LifeEntry], isDelta: Bool) -> [LifeEntry] {
        if !isDelta {
            let pending = current.filter { ($0.syncStatus ?? "synced") != "synced" }
            let remote = incoming.filter { ($0.deletedAt ?? "").isEmpty }
            return legacySorted(pending + remote)
        }
        var map = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for item in incoming {
            if let deleted = item.deletedAt, !deleted.isEmpty {
                map.removeValue(forKey: item.id)
            } else {
                var synced = item
                synced.syncStatus = "synced"
                map[item.id] = synced
            }
        }
        return legacySorted(Array(map.values))
    }

    private func legacySorted(_ entries: [LifeEntry]) -> [LifeEntry] {
        entries
            .map { ($0, FormatUtils.parseFlexDate($0.occurredAt) ?? .distantPast) }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.id > $1.0.id
            }
            .map(\.0)
    }

    /// 1 万条增量合并：后台版本必须与旧同步实现产生完全相同的顺序。
    func test01_TenThousandEntryMergeMatchesLegacyOrdering() async {
        let current = (1...10_000).map { entry($0, ($0 % 28) + 1) }
        var incoming = (5_000...5_400).map {
            entry($0, (($0 + 3) % 28) + 1, updatedAt: "2026-10-20T10:00:00+08:00")
        }
        incoming.append(entry(123, 1, deletedAt: "2026-10-20T11:00:00+08:00"))
        incoming.append(entry(20_001, 15, updatedAt: "2026-10-21T10:00:00+08:00"))

        let fast = await Task.detached(priority: .userInitiated) {
            SyncManager.mergedEntries(current: current, incoming: incoming, isDelta: true)
        }.value
        let legacy = legacyMerged(current: current, incoming: incoming, isDelta: true)

        XCTAssertEqual(fast.count, legacy.count)
        XCTAssertEqual(fast.map(\.id), legacy.map(\.id), "后台合并不得改变任何排序/软删除语义")
        XCTAssertFalse(fast.contains(where: { $0.id == 123 }), "软删除必须仍然生效")
    }

    /// 注水合并：磁盘补全历史，内存本地写入优先；pending 状态与账目/发件箱绝不能丢。
    func test05_HydrationMergePreservesPendingLocalDataAndOutbox() {
        var localPending = entry(-1, 1)
        localPending.syncStatus = "pending_create"
        localPending.title = "刚写的本地草稿"

        var localSynced = entry(5, 5, updatedAt: "2026-10-22T10:00:00+08:00")
        localSynced.title = "本地较新标题"
        localSynced.syncStatus = "synced"

        var diskPending = entry(-2, 2)
        diskPending.syncStatus = "pending_create"

        let current = LocalArchiveSnapshot(
            entries: [localPending, localSynced],
            transactions: [Transaction(
                id: 10,
                amount: 100,
                type: "expense",
                category: "餐饮",
                title: "本地账目",
                occurredAt: "2026-10-20T10:00:00+08:00"
            )],
            outbox: [OutboxItem(kind: .createEntry, localTempId: -1)]
        )
        let loaded = LocalArchiveSnapshot(
            entries: [entry(5, 5, updatedAt: "2026-10-01T10:00:00+08:00"), diskPending],
            transactions: [Transaction(
                id: 20,
                amount: 200,
                type: "expense",
                category: "交通",
                title: "磁盘账目",
                occurredAt: "2026-10-19T10:00:00+08:00"
            )],
            outbox: [OutboxItem(kind: .deleteEntry, localTempId: -2, targetServerId: 9)]
        )

        let merged = SyncManager.mergedHydratedSnapshot(current: current, loaded: loaded)
        XCTAssertEqual(Set(merged.entries.map(\.id)), Set([-1, 5, -2]))
        XCTAssertEqual(merged.entries.first { $0.id == -1 }?.syncStatus, "pending_create")
        XCTAssertEqual(merged.entries.first { $0.id == -2 }?.syncStatus, "pending_create",
                       "磁盘里的 pending 行不能被强制改成 synced")
        XCTAssertEqual(merged.entries.first { $0.id == 5 }?.title, "本地较新标题",
                       "同一 id 内存里的本地写入优先")
        XCTAssertEqual(Set(merged.transactions.map(\.id)), Set([10, 20]))
        XCTAssertEqual(merged.outbox.count, 2, "本地与磁盘的发件箱必须取并集")
    }

    /// 内容不变（但数组是重新解码出来的实例）→ 指纹相同；单条更新 → 指纹不同。
    func test02_FingerprintStableWhenUnchangedAndChangesOnSingleUpdate() {
        let original = (1...3_000).map { entry($0, ($0 % 28) + 1) }
        let decodedCopy = original.map { $0 }
        XCTAssertEqual(
            SyncManager.entryFingerprint(original),
            SyncManager.entryFingerprint(decodedCopy),
            "等价数据必须得到相同指纹"
        )

        var updated = original
        updated[1_500].updatedAt = "2026-10-22T12:00:00+08:00"
        XCTAssertNotEqual(
            SyncManager.entryFingerprint(original),
            SyncManager.entryFingerprint(updated),
            "单条 updatedAt 变化必须被指纹捕获"
        )

        var statusChanged = original
        statusChanged[0].syncStatus = "pending_create"
        XCTAssertNotEqual(
            SyncManager.entryFingerprint(original),
            SyncManager.entryFingerprint(statusChanged),
            "本地同步状态变化（不改 updatedAt）也必须被捕获"
        )
    }

    /// 附件换签只改 URL：指纹必须变化，否则大档案下 UI 不会刷新相纸地址。
    func test03_FingerprintDetectsAttachmentURLRefresh() {
        var original = entry(1, 1)
        original.attachments = [Attachment(
            id: 10,
            objectKey: "media/a.jpg",
            originalFilename: "a.jpg",
            mimeType: "image/jpeg",
            size: 100,
            width: 800,
            height: 600,
            url: "https://example.com/a.jpg?exp=1&sig=old",
            thumbnailUrl: nil,
            createdAt: nil
        )]
        var refreshed = original
        refreshed.attachments[0].url = "https://example.com/a.jpg?exp=2&sig=new"

        XCTAssertNotEqual(
            SyncManager.entryFingerprint([original]),
            SyncManager.entryFingerprint([refreshed])
        )
    }

    func test04_TransactionFingerprintTracksCountsAndUpdates() {
        let base = (1...100).map { i in
            Transaction(
                id: i,
                amount: Int64(i) * 100,
                type: "expense",
                category: "餐饮",
                title: "账目 \(i)",
                occurredAt: "2026-10-01T10:00:00+08:00",
                updatedAt: "2026-10-01T10:00:00+08:00"
            )
        }
        XCTAssertEqual(SyncManager.transactionFingerprint(base), SyncManager.transactionFingerprint(base.map { $0 }))

        var changed = base
        changed[50].amount += 1
        XCTAssertNotEqual(SyncManager.transactionFingerprint(base), SyncManager.transactionFingerprint(changed))
    }
}
