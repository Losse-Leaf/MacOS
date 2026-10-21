import XCTest
@testable import LooseLeaf

/// 「重新上传」接口的行为约束
///
/// 背景：条目有「待同步 / 同步失败 / 已同步」三种同步状态。
/// 早先只有「同步失败」才有重试入口 —— 而「待同步」的条目同样可能卡住
/// （发件箱死信被丢弃、进程在同步途中被杀），那时用户没有任何办法
/// 让它重新上去。「待同步」与「同步失败」只是同一件事的两个阶段，
/// 重传入口必须一致；并且断一次网会积压几十条，需要批量重传。
@MainActor
final class ReuploadTests: XCTestCase {

    private func makeEntry(id: Int, status: String?) -> LifeEntry {
        var entry = LifeEntry(
            id: id,
            type: EntryType.life.rawValue,
            title: "第 \(id) 条",
            content: "正文",
            occurredAt: "2026-09-01T10:00:00+08:00"
        )
        entry.syncStatus = status
        return entry
    }

    // MARK: - 需要重传的条目统计

    func test01_CountsEntriesNeedingUpload() {
        let appState = AppState.shared
        let original = appState.entries
        defer { appState.entries = original }

        appState.entries = [
            makeEntry(id: 1, status: "synced"),
            makeEntry(id: 2, status: "pending_create"),
            makeEntry(id: 3, status: "failed"),
            makeEntry(id: 4, status: nil),        // nil 视为已同步
            makeEntry(id: 5, status: "synced")
        ]
        XCTAssertEqual(appState.entriesNeedingUpload, 2, "只有待同步与同步失败需要重传")
    }

    func test02_CountsTransactionsNeedingUpload() {
        let appState = AppState.shared
        let original = appState.transactions
        defer { appState.transactions = original }

        var pending = Transaction(id: 1, amount: 100, type: "expense", category: "餐饮", title: "a")
        pending.syncStatus = "pending_create"
        var failed = Transaction(id: 2, amount: 200, type: "expense", category: "餐饮", title: "b")
        failed.syncStatus = "failed"
        let ok = Transaction(id: 3, amount: 300, type: "expense", category: "餐饮", title: "c")

        appState.transactions = [pending, failed, ok]
        XCTAssertEqual(appState.transactionsNeedingUpload, 2)
    }

    // MARK: - 批量重传

    func test03_ReuploadAllWithNothingPendingIsNoop() {
        let appState = AppState.shared
        let original = appState.entries
        defer { appState.entries = original }

        appState.entries = [makeEntry(id: 1, status: "synced")]
        XCTAssertEqual(appState.reuploadAllPending(), 0, "没有待同步内容时不应做任何事")
    }

    /// 待同步 / 同步失败都会被计入重传范围
    func test04_ReuploadAllCoversBothPendingAndFailed() {
        let appState = AppState.shared
        let original = appState.entries
        let originalTx = appState.transactions
        defer {
            appState.entries = original
            appState.transactions = originalTx
        }

        appState.entries = [
            makeEntry(id: 1, status: "pending_create"),
            makeEntry(id: 2, status: "failed"),
            makeEntry(id: 3, status: "synced")
        ]
        var tx = Transaction(id: 1, amount: 100, type: "expense", category: "餐饮", title: "a")
        tx.syncStatus = "pending_create"
        appState.transactions = [tx]

        // 会真的发起网络请求；这里只验证计数与分流逻辑
        let count = appState.reuploadAllPending()
        XCTAssertEqual(count, 3, "2 条散页 + 1 条账目")
    }
}
