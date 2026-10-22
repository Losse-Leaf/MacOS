import XCTest
@testable import LooseLeaf

/// 快照落盘的关键不变式（MC-09 / MC-10）
///
/// MC-10（关键写入立即刷盘）：离线入发件箱的记录**只存在于本地** ——
/// 服务端还没有它们。此时若在 0.35 秒防抖窗口内崩溃，
/// 这条记录就**永久丢失**（既没到服务端，本地快照也没落盘）。
/// 所以关键写入必须**不等**防抖窗口就落盘。
///
/// MC-09（退出落盘异步化）：整份快照的 JSON 编码是落盘的大头
/// （实测 2000 条约 9ms、5 万条约 220ms）。在主线程同步等待 ⇒
/// 用户按 ⌘Q 时界面冻住。所以退出前的落盘必须走**异步**路径。
@MainActor
final class SnapshotDurabilityTests: XCTestCase {

    private var tempDir: URL!
    private var savedSnapshot: LocalArchiveSnapshot!
    private var hadOverride: URL?

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("looseleaf-snapshot-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        hadOverride = SyncManager.snapshotFileURLOverride
        SyncManager.snapshotFileURLOverride = tempDir.appendingPathComponent("snapshot.json")
        savedSnapshot = SyncManager.shared.currentSnapshot()
    }

    override func tearDown() async throws {
        SyncManager.snapshotFileURLOverride = hadOverride
        // 还原内存快照，避免污染其它用例
        if let savedSnapshot {
            SyncManager.shared.saveSnapshot(savedSnapshot)
        }
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var snapshotURL: URL { SyncManager.snapshotFileURL }

    // 注：标记一律写在 `lastEntriesSyncCursor` 上 ——
    // `saveSnapshot` 会把 `updatedAt` 覆写成当前时间，用它当标记必然被冲掉。

    // MARK: - MC-10：关键写入必须立即落盘

    /// 关键写入应当在**远小于** 0.35 秒防抖窗口的时间内就出现在磁盘上
    func test01_CriticalWriteLandsOnDiskImmediately() async throws {
        let marker = LocalArchiveSnapshot(
            entries: [],
            transactions: [],
            lastEntriesSyncCursor: "critical-marker-\(UUID().uuidString)"
        )
        SyncManager.shared.saveSnapshot(marker, critical: true)

        // 最多等 150ms（远小于 350ms 防抖窗口）就该看到文件
        let deadline = Date().addingTimeInterval(0.15)
        var appeared = FileManager.default.fileExists(atPath: snapshotURL.path)
        while !appeared && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
            appeared = FileManager.default.fileExists(atPath: snapshotURL.path)
        }
        XCTAssertTrue(
            appeared,
            "关键写入必须在 150ms 内落盘（防抖窗口是 350ms）—— 否则崩溃时这条只存在于本地的记录会永久丢失"
        )
    }

    /// 非关键写入**仍然**走防抖窗口（不能为了关键路径把普通写入也变成同步落盘，
    /// 那会把主线程拖慢 —— 一次全量刷新会触发 5 次 save）
    func test02_NormalWriteStillDebounces() async throws {
        let marker = LocalArchiveSnapshot(
            entries: [],
            transactions: [],
            lastEntriesSyncCursor: "normal-marker-\(UUID().uuidString)"
        )
        SyncManager.shared.saveSnapshot(marker, critical: false)

        // 立刻看：不应该已经落盘（还在 0.35s 窗口里）
        try await Task.sleep(nanoseconds: 60_000_000)
        let earlyExists = FileManager.default.fileExists(atPath: snapshotURL.path)
        let earlyContent = earlyExists
            ? (try? String(contentsOf: snapshotURL, encoding: .utf8)) ?? ""
            : ""
        XCTAssertFalse(
            earlyContent.contains("normal-marker"),
            "普通写入必须留在 0.35s 防抖窗口内，不能被关键路径带成同步落盘"
        )

        // 等过窗口后应当落盘
        let deadline = Date().addingTimeInterval(1.0)
        var landed = false
        while !landed && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
            if let content = try? String(contentsOf: snapshotURL, encoding: .utf8),
               content.contains("normal-marker") {
                landed = true
            }
        }
        XCTAssertTrue(landed, "普通写入在防抖窗口过后必须落盘")
    }

    // MARK: - MC-09：退出落盘走异步路径

    /// 异步落盘必须**真的把数据写出去**（否则退出时数据就丢了）
    func test03_AsyncFlushActuallyWritesToDisk() async throws {
        let marker = LocalArchiveSnapshot(
            entries: [],
            transactions: [],
            lastEntriesSyncCursor: "async-flush-marker-\(UUID().uuidString)"
        )
        SyncManager.shared.saveSnapshot(marker, critical: true)
        // 等关键写入先落盘，确保磁盘上有基线
        try await Task.sleep(nanoseconds: 120_000_000)

        // 再来一次普通保存（会走防抖），随后调用异步退出落盘
        let second = LocalArchiveSnapshot(
            entries: [],
            transactions: [],
            lastEntriesSyncCursor: "async-flush-second-\(UUID().uuidString)"
        )
        SyncManager.shared.saveSnapshot(second, critical: false)
        try await Task.sleep(nanoseconds: 20_000_000)

        await SyncManager.shared.flushSnapshotToDiskIfNeededAsync()

        let content = (try? String(contentsOf: snapshotURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(
            content.contains("async-flush-second"),
            "异步退出落盘必须真的把最新快照写出去 —— 否则退出时的修改就丢了"
        )
    }

    /// 异步落盘**不阻塞调用方**：主线程在 await 期间应保持可响应
    ///
    /// 这里量的是「await 期间主线程还能跑别的任务」——
    /// 若实现退化成同步阻塞（diskWriteQueue.sync），这个计数会是 0。
    func test04_AsyncFlushDoesNotBlockMainThread() async throws {
        let marker = LocalArchiveSnapshot(
            entries: (1...2_000).map { i in
                LifeEntry(
                    id: i,
                    type: "life",
                    title: "第 \(i) 则",
                    content: String(repeating: "正文内容。", count: 40),
                    occurredAt: "2026-10-01T10:00:00+08:00"
                )
            },
            transactions: [],
            lastEntriesSyncCursor: "blocking-check-\(UUID().uuidString)"
        )
        SyncManager.shared.saveSnapshot(marker, critical: false)
        try await Task.sleep(nanoseconds: 20_000_000)

        var ticks = 0
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                ticks += 1
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
        }
        await SyncManager.shared.flushSnapshotToDiskIfNeededAsync()
        ticker.cancel()

        XCTAssertGreaterThan(
            ticks, 0,
            "异步落盘期间主线程必须还能跑任务（若退化成 diskWriteQueue.sync，这里会是 0）"
        )
    }
}
