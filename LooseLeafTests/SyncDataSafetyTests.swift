import XCTest
@testable import LooseLeaf

/// 同步链路的**数据安全**回归测试
///
/// 这批测试针对的是一次深度体检挖出的四条 P0 —— 它们的共同后果是
/// **本地数据丢失**或**服务端出现重复条目**，而且都是静默发生的。
@MainActor
final class SyncDataSafetyTests: XCTestCase {

    // MARK: - 1. 首屏投递不能把本地档案整体替换掉

    /// `mergeEntries(_:isDelta: false)` 是「本地档案整体替换为远端列表」。
    /// 首屏回调只带了**第 1 页**，若用它做全量语义，
    /// 本地几千条会被瞬间截断成 100 条，且这个截断态会写进磁盘快照。
    func test01_IncrementalMergeDoesNotDropLocalEntries() {
        let local = (1...50).map { i -> LifeEntry in
            var e = LifeEntry(
                id: i,
                type: EntryType.life.rawValue,
                title: "本地 \(i)",
                content: "本地内容 \(i)",
                occurredAt: "2026-09-01T10:00:00+08:00"
            )
            e.syncStatus = "synced"
            return e
        }
        // 远端只来了 3 条（模拟「第 1 页」）
        let remote = (100...102).map { i -> LifeEntry in
            var e = LifeEntry(
                id: i,
                type: EntryType.life.rawValue,
                title: "远端 \(i)",
                content: "远端内容 \(i)",
                occurredAt: "2026-09-02T10:00:00+08:00"
            )
            e.syncStatus = "synced"
            return e
        }

        let merged = SyncManager.mergedEntries(current: local, incoming: remote, isDelta: true)
        XCTAssertEqual(merged.count, 53, "增量合并不应丢掉任何本地条目")
        XCTAssertTrue(merged.contains { $0.id == 1 }, "本地第 1 条必须还在")
        XCTAssertTrue(merged.contains { $0.id == 102 }, "远端新条目必须进来")
    }

    /// 全量语义本身是对的（远端权威），但**只应在拿到全部数据后**使用。
    func test02_FullMergeKeepsUnsyncedLocalItems() {
        var pending = LifeEntry(
            id: -1,
            type: EntryType.life.rawValue,
            title: "待同步",
            content: "还没传上去",
            occurredAt: "2026-09-03T10:00:00+08:00"
        )
        pending.syncStatus = "pending_create"

        let remote = [LifeEntry(
            id: 10,
            type: EntryType.life.rawValue,
            title: "远端",
            content: "远端内容",
            occurredAt: "2026-09-01T10:00:00+08:00"
        )]
        let merged = SyncManager.mergedEntries(current: [pending], incoming: remote, isDelta: false)
        XCTAssertEqual(merged.count, 2, "全量合并也要保住未同步的本地条目")
        XCTAssertTrue(merged.contains { $0.id == -1 })
    }

    // MARK: - 2. 软删除要能把条目真正移除

    func test03_IncrementalMergeRemovesSoftDeleted() {
        var deleted = LifeEntry(
            id: 7,
            type: EntryType.life.rawValue,
            title: "已删",
            content: "内容",
            occurredAt: "2026-09-01T10:00:00+08:00"
        )
        deleted.deletedAt = "2026-09-05T00:00:00+08:00"

        let local = [LifeEntry(
            id: 7,
            type: EntryType.life.rawValue,
            title: "已删",
            content: "内容",
            occurredAt: "2026-09-01T10:00:00+08:00"
        )]
        let merged = SyncManager.mergedEntries(current: local, incoming: [deleted], isDelta: true)
        XCTAssertTrue(merged.isEmpty, "服务端标记删除的条目必须从本地移除")
    }

    // MARK: - 3. 乐观条目用**本地 id**而不是服务端 id

    /// 乐观条目的本地 id 必须是**负数**。
    /// 关键：服务端 id 从 1 开始，负数区间天然与它不冲突，
    /// 这样「本地临时 id」与服务端正式 id 可以放在同一个数组里而不混淆。
    func test04_OptimisticEntriesUseNegativeIDs() {
        let entry = SyncManager.makeLocalTempId()
        XCTAssertLessThan(entry, 0, "乐观条目的本地 id 必须是负数")
        let another = SyncManager.makeLocalTempId()
        XCTAssertNotEqual(entry, another, "每次乐观写入都要拿到不同的临时 id")
    }

    // MARK: - 4. 时间戳文案

    func test05_CompactTimeLabelRules() {
        // 同一分钟 → 折叠
        let a = FormatUtils.formatBeijingDate(
            FormatUtils.parseFlexDate("2026-09-01T10:00:00+08:00")!
        )
        let b = FormatUtils.formatBeijingDate(
            FormatUtils.parseFlexDate("2026-09-01T10:00:00+08:00")!
        )
        XCTAssertEqual(AppState.compactTimeLabel(a, previous: b), "")

        // 同一天不同分钟 → 只显时刻
        let c = FormatUtils.formatBeijingDate(
            FormatUtils.parseFlexDate("2026-09-01T10:05:00+08:00")!
        )
        XCTAssertEqual(AppState.compactTimeLabel(c, previous: a), "10:05")

        // 跨天 → 显日期
        let d = FormatUtils.formatBeijingDate(
            FormatUtils.parseFlexDate("2026-09-02T10:05:00+08:00")!
        )
        XCTAssertEqual(AppState.compactTimeLabel(d, previous: c), "9月2日")
    }
}
