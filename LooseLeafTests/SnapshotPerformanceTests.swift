import XCTest
import SwiftUI
import AppKit
@testable import LooseLeaf

/// 快照与同步链路的性能基准（MC-07 / MC-08 / MC-09 / MC-10）
///
/// 这些是**基准**而非断言（不同机器差异大）：只打印数据，
/// 并对明显回归设宽松上限（取三轮最小值，最不受机器负载干扰）。
///
/// 背景：这些项在台账里都是 P3，但「P3」是当时的判断，不是测出来的。
/// 这里把它们量化 —— 先有数字，再决定改不改、怎么改。
@MainActor
final class SnapshotPerformanceTests: XCTestCase {

    private var results: [(String, TimeInterval)] = []

    override func tearDown() async throws {
        print("──────── 快照 / 同步性能 ────────")
        for (name, elapsed) in results {
            let flag = elapsed > 0.1 ? "  ⚠️ 慢" : ""
            print(String(format: "  %-46@ %7.2f ms%@", name as NSString, elapsed * 1000, flag as NSString))
        }
        results = []
    }

    /// 跑三轮取最小值
    private func measure(_ name: String, iterations: Int = 1, _ block: () -> Void) {
        var best = TimeInterval.greatestFiniteMagnitude
        for _ in 0..<3 {
            let start = Date()
            for _ in 0..<iterations { block() }
            best = min(best, Date().timeIntervalSince(start) / Double(iterations))
        }
        results.append((name, best))
        print(String(format: "  %-46@ %7.2f ms", name as NSString, best * 1000))
    }

    // MARK: - 合成档案

    /// 造一份规模接近真实大档案的条目集
    private func syntheticEntries(_ count: Int) -> [LifeEntry] {
        (1...count).map { i in
            LifeEntry(
                id: i,
                type: "life",
                title: "第 \(i) 则手稿 · 某日的寻常记录",
                content: String(repeating: "这是第 \(i) 则手稿的正文内容，", count: 40),
                occurredAt: "2026-10-\(String(format: "%02d", (i % 28) + 1))T10:00:00+08:00",
                location: "某市某区某街道 \(i) 号",
                cityCode: "110100",
                cityName: "北京市",
                attachments: [],
                createdAt: "2026-10-01T10:00:00+08:00",
                updatedAt: "2026-10-01T10:00:00+08:00"
            )
        }
    }

    // MARK: - MC-07：applySnapshot 的全量深比较

    /// 每次同步都要做一次 `self.entries != snap.entries`，
    /// 这是 **O(N) 次深比较**（每条含长正文字符串）。
    /// 这里量两种最坏情况：**末尾**才变（比较要走完全部条目）。
    func test01_ApplySnapshotDeepComparisonCost() {
        let entries = syntheticEntries(2_000)
        // 内容完全相同、但不是同一批实例（模拟「重新解码出来的等价数据」）
        let same = entries.map { $0 }
        var changedAtEnd = entries
        changedAtEnd[changedAtEnd.count - 1].content += "（改了）"

        measure("MC-07 深比较 2000 条 · 内容未变（走完全部）", iterations: 5) {
            _ = entries != same
        }
        measure("MC-07 深比较 2000 条 · 仅末条变更（最坏路径）", iterations: 5) {
            _ = entries != changedAtEnd
        }
    }

    /// 对照：只要长度/顺序指纹一致就能判定的成本
    func test02_CheapFingerprintComparisonCost() {
        let entries = syntheticEntries(2_000)
        let ids = entries.map { $0.id }
        let idsAgain = entries.map { $0.id }
        measure("MC-07 对照 · id 数组比较 2000 条", iterations: 5) {
            _ = ids != idsAgain
        }
    }

    // MARK: - MC-09 / MC-10：快照落盘的成本构成

    /// 退出前落盘 = JSON 编码整份快照 + 写盘。
    /// 编码是**主线程阻塞**的大头（写盘本身在后台队列上）。
    func test03_SnapshotJSONEncodeCost() {
        let snapshot = LocalArchiveSnapshot(
            entries: syntheticEntries(2_000),
            transactions: (1...200).map { i in
                Transaction(
                    id: i,
                    amount: Int64(i) * 100,
                    type: "expense",
                    category: "数码器材",
                    title: "第 \(i) 笔账目",
                    occurredAt: "2026-10-01T10:00:00+08:00"
                )
            }
        )
        measure("MC-09 快照 JSON 编码（2000 条 + 200 账）", iterations: 3) {
            _ = try? JSONEncoder().encode(snapshot)
        }
    }

    // MARK: - MC-08：单卡重绘成本（键盘焦点移动的放大倍数）

    /// 键盘焦点每移动一格，理论上只有**两张卡**的状态变了（前一张失焦、后一张聚焦）。
    ///
    /// 注意：测量装置本身有**很大的固定开销**（实测约 1.8s）——
    /// 那不是重绘，而是 RunLoop 空转期间 AppState 的后台活动（网络监听、快照落盘等）
    /// 在测试进程里一并跑掉了。所以这里必须**同时测一个「无效变更」的对照组**，
    /// 用「实测 − 对照」得到真正的净重绘成本。
    ///
    /// 关键：要量的是**重绘增量**，不是首次挂载 ——
    /// SwiftUI 首次挂载任意视图有约 35~75ms 的固定初始化成本，
    /// 把它算进来会让「重绘」的数字完全失真。
    /// 因此这里**挂载一次**，之后只改焦点再量布局+绘制，取增量。
    func test04_KeyboardFocusRerenderCost() {
        let entries = syntheticEntries(60)
        let holder = FocusHolder()

        let hosting = NSHostingView(rootView:
            StreamLikeView(holder: holder, entries: entries, actions: TimelineEntryActions())
                .frame(width: 1080, height: 800)
        )
        hosting.frame = CGRect(x: 0, y: 0, width: 1080, height: 800)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
        }

        /// 一次「焦点变更」的测量：改焦点 → 让 SwiftUI 落到布局与绘制上
        func measureFocusChange(_ label: String, mutate: () -> Void) -> TimeInterval {
            var best = TimeInterval.greatestFiniteMagnitude
            for _ in 0..<2 {
                let start = Date()
                mutate()
                // 让 SwiftUI 把这次变更落到布局与绘制上
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                hosting.layoutSubtreeIfNeeded()
                if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                    hosting.cacheDisplay(in: hosting.bounds, to: rep)
                }
                best = min(best, Date().timeIntervalSince(start))
            }
            results.append((label, best))
            print(String(format: "  %-46@ %7.2f ms", label as NSString, best * 1000))
            return best
        }

        // 对照组：把焦点设成**同一个值** —— 不触发任何失效。
        // 它量到的是「测量装置本身」（RunLoop 空转 + 布局 + 绘制）的固定开销。
        holder.focusedId = 1
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let control = measureFocusChange("MC-08 对照 · 无效变更（测量装置固定开销）") {
            holder.focusedId = 1
        }

        // 实验组：焦点真的移动
        var step = 1
        let actual = measureFocusChange("MC-08 焦点移动一次 · 60 张卡整列重绘") {
            step = (step % 5) + 1
            holder.focusedId = step
        }

        results.append(("MC-08 净重绘成本（实测 − 对照）", max(0, actual - control)))
        print(String(format: "  %-46@ %7.2f ms", "MC-08 净重绘成本（实测 − 对照）" as NSString, max(0, actual - control) * 1000))
    }

    /// 焦点承载者（可观察）
    final class FocusHolder: ObservableObject {
        @Published var focusedId: Int? = nil
    }

    /// 模拟时间流的一列卡片：焦点变化会让 ForEach 全体重新求值
    struct StreamLikeView: View {
        @ObservedObject var holder: FocusHolder
        let entries: [LifeEntry]
        /// 关键：**全列共享同一个 actions 实例**（与真实 StreamView 一致）。
        /// `TimelineEntryActions` 是引用类型且行为恒定 —— 共享后 SwiftUI
        /// 才能跳过「内容没变的卡片」。若逐卡新建，测出来的就是
        /// 「本来就该被跳过却没被跳过」的最坏情况，不是真实开销。
        let actions: TimelineEntryActions
        var body: some View {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    TimelineEntryCardView(
                        entry: entry,
                        timeLabel: "10:00",
                        transaction: nil,
                        isKeyboardFocused: holder.focusedId == entry.id,
                        actions: actions
                    )
                    .frame(width: 900, height: 160)
                }
            }
        }
    }
}
