import XCTest
import SwiftUI
import AppKit
@testable import LooseLeaf

/// UI 层**全功能操作走查**（模拟真实用户逐个操作，量主线程阻塞）
///
/// 为什么要有这个：
/// 之前的走查（`ArchiveWalkthroughTests`）停在 **API 层** —— 能证明「功能通不通」，
/// 但证明不了「点下去卡不卡」。用户真正感受到的是**主线程被堵住多久**。
///
/// 度量方式：
///   1. 把主界面真正挂进 `NSHostingView`（走真实 SwiftUI 渲染管线）
///   2. 逐个模拟用户操作（点卡片、开弹窗、切页面、打字、搜索、滚动…）
///   3. 量「操作 + 随后的布局/绘制」的**同步**耗时
///
/// 判定基准：**一帧 = 16ms**（60fps）。单次操作超过一帧，用户就能感觉到「顿一下」；
/// 超过 100ms 就是「转圈」；超过 500ms 就是「卡死」。
@MainActor
final class UIInteractionWalkthroughTests: XCTestCase {

    /// 一帧预算（60fps）
    private static let frameBudget: TimeInterval = 1.0 / 60.0
    /// 转圈阈值
    private static let spinnerThreshold: TimeInterval = 0.10
    /// 卡死阈值
    private static let freezeThreshold: TimeInterval = 0.50

    private var report: [(String, TimeInterval)] = []
    private var redrawReport: [(String, Int)] = []
    private var hosting: NSHostingView<AnyView>!

    override func tearDown() async throws {
        if !report.isEmpty {
            print("──────── UI 操作走查 · 主线程同步耗时 ────────")
            for (label, elapsed) in report.sorted(by: { $0.1 > $1.1 }) {
                let verdict: String
                if elapsed >= Self.freezeThreshold { verdict = "❌ 卡死" }
                else if elapsed >= Self.spinnerThreshold { verdict = "🔴 转圈" }
                else if elapsed >= Self.frameBudget { verdict = "🟡 顿帧" }
                else { verdict = "✅ 流畅" }
                print(String(format: "  %-42@ %7.1f ms  %@",
                             label as NSString, elapsed * 1000, verdict as NSString))
            }
            let worst = report.map(\.1).max() ?? 0
            print(String(format: "  最慢一次: %.1f ms", worst * 1000))
        }
        if !redrawReport.isEmpty {
            print("──────── UI 操作走查 · 卡片重算次数 ────────")
            for (label, count) in redrawReport {
                let verdict = count > 20 ? "❌ 整列重算" : (count > 5 ? "🟡 偏多" : "✅ 精准")
                print(String(format: "  %-42@ %4d 张   %@", label as NSString, count, verdict as NSString))
            }
        }
        report = []
        redrawReport = []
        hosting = nil
        try await super.tearDown()
    }

    // MARK: - 基础设施

    /// 注入确定性的内容，模拟一个「用了一段时间」的档案
    private func seed() {
        let appState = AppState.shared
        let bodies = [
            "把书架靠到窗边，下午的光正好落在书脊上。顺手拍了一张，纸的味道还没散。",
            "今天走了很久的路，鞋底沾着傍晚的尘土。回来路上买了一支很便宜的钢笔。",
            "雨下了一整个下午。屋里很安静，听得见雨点打在玻璃上的声音。",
            "整理旧物，翻出来三年前的笔记本，字迹还很淡。有些事像是昨天才发生的。",
            "和朋友在街角的小店坐了很久，什么正经事也没聊，就是坐着。",
            "清晨五点醒，窗外还是灰蓝色。给自己煮了咖啡，等天亮。",
            "看完了一本很厚的书，合上的时候有点舍不得。",
            "搬了家，把所有书重新码了一遍。新的排列方式看起来像另一批书。",
            "公园的银杏开始黄了，踩上去有很轻的脆响。",
            "煮了一锅汤，厨房里全是热气。冬天就该这样过。"
        ]
        var entries: [LifeEntry] = []
        for i in 0..<60 {
            let day = String(format: "%02d", (i % 28) + 1)
            entries.append(LifeEntry(
                id: i + 1,
                type: EntryType.life.rawValue,
                title: "第 \(i + 1) 条随笔",
                content: bodies[i % bodies.count],
                occurredAt: "2026-09-\(day)T10:00:00+08:00",
                cityCode: "330100",
                cityName: "杭州市"
            ))
        }
        appState.entries = entries
        appState.transactions = (0..<20).map { i in
            var tx = Transaction(
                id: i + 1,
                amount: Int64(2500 + i * 137),
                type: i % 3 == 0 ? "income" : "expense",
                category: "餐饮",
                title: "第 \(i + 1) 笔"
            )
            tx.occurredAt = "2026-09-\(String(format: "%02d", (i % 28) + 1))T12:00:00+08:00"
            return tx
        }
        appState.wishes = (0..<12).map { i in
            Wish(id: i + 1, title: "第 \(i + 1) 个心愿", kind: "item", note: "备注")
        }
        appState.projects = (0..<8).map { i in
            Project(id: i + 1, title: "第 \(i + 1) 个造物", description: "描述")
        }
        appState.footprints = (0..<8).map { i in
            Footprint(id: i + 1, cityCode: "330100", cityName: "杭州市", visitedAt: "2026-09-10T10:00:00+08:00")
        }
    }

    /// 挂载一个视图并强制布局 + 位图绘制（覆盖 body 求值、排版、绘制）
    private func mount<V: View>(_ view: V, size: CGSize) {
        hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.layoutSubtreeIfNeeded()
    }

    /// 强制当前挂载视图重排 + 重绘
    private func flush() {
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
        }
    }

    /// 测量一次「用户操作 + 随之而来的重排重绘」的同步耗时
    private func measure(_ label: String, _ action: () -> Void) {
        let start = Date()
        action()
        flush()
        let elapsed = Date().timeIntervalSince(start)
        report.append((label, elapsed))
        print(String(format: "  %-42@ %7.1f ms", label as NSString, elapsed * 1000))
    }

    /// 测量一次操作让**多少张卡片重新求值 body**。
    ///
    /// 这是比耗时更本质的指标：SwiftUI 只在视图值真的变了时才重绘卡片。
    /// 一旦某次无关操作让整列 60 张卡全部重算，用户看到的就是「点哪儿都卡一下」；
    /// 而时间流滚动时每一帧都会重复这件事。
    private func measureRedraws(_ label: String, _ action: () -> Void) {
        TimelineRenderCounter.reset()
        action()
        flush()
        let redraws = TimelineRenderCounter.value
        redrawReport.append((label, redraws))
        print(String(format: "  %-42@ 重算 %4d 张卡", label as NSString, redraws))
    }

    // MARK: - 走查

    /// 打开主界面（时间流），逐个模拟用户的每一次点击
    func test01_TimeStreamInteractions() throws {
        seed()
        let appState = AppState.shared
        let size = CGSize(width: 1280, height: 820)

        // 挂载时间流（首次）
        let mountStart = Date()
        mount(StreamView(appState: appState), size: size)
        flush()
        report.append(("① 打开时间流（首次挂载）", Date().timeIntervalSince(mountStart)))

        // 1. 点击一张卡片（打开详情）
        if let first = appState.entries.first {
            measure("② 点击卡片（打开详情）") {
                appState.highlightedEntry = first
            }
            appState.highlightedEntry = nil
            flush()
        }

        // 2. 双击卡片（独立详情窗口）
        if let first = appState.entries.first {
            measure("③ 双击卡片（独立详情窗口）") {
                appState.detailWindowEntry = first
            }
            appState.detailWindowEntry = nil
            flush()
        }

        // 3. 打开记一笔弹窗
        measure("④ 点击「记一笔」（创作弹窗）") {
            appState.showNewEntrySheet = true
        }
        appState.showNewEntrySheet = false
        flush()

        // 3.5 各操作分别量「重算了多少张卡」
        measureRedraws("④b 打开创作弹窗 → 卡片重算") {
            appState.showNewEntrySheet = true
        }
        appState.showNewEntrySheet = false
        flush()
        measureRedraws("②b 点击卡片 → 卡片重算") {
            appState.highlightedEntry = appState.entries.first
        }
        appState.highlightedEntry = nil
        flush()
        measureRedraws("⑦b 点「同步」→ 卡片重算") {
            appState.isOnline = true
        }

        // 4. 逐个切换侧栏页面
        for section in WorkbenchSection.contentSections {
            measure("⑤ 切到「\(section.rawValue)」页") {
                appState.activeSection = section
            }
        }
        appState.activeSection = .stream
        flush()

        // 5. 打开全局检索
        measure("⑥ 打开全局检索") {
            appState.showSearchModal = true
        }
        appState.showSearchModal = false
        flush()

        // 5.5 切换侧栏时的重算量
        for section in WorkbenchSection.contentSections {
            measureRedraws("⑤b 切到「\(section.rawValue)」→ 卡片重算") {
                appState.activeSection = section
            }
        }
        appState.activeSection = .stream
        flush()

        // 6. 触发一次全量刷新（模拟点「同步」）
        measure("⑦ 点「同步」（全量刷新）") {
            appState.isOnline = true
        }
    }

    /// 在创作弹窗里逐字输入：每一次按键都会让弹窗重算
    func test02_ComposerTypingCost() throws {
        seed()
        let appState = AppState.shared
        let size = CGSize(width: 760, height: 660)

        let modal = NewEntryModal(
            appState: appState,
            initialKind: "life",
            initialProjectId: nil,
            initialCityCode: nil,
            initialCityName: nil
        ) { }
        mount(modal, size: size)
        flush()

        // 模拟逐字输入：每次改一个字符
        let draft = EntryDraft()
        var text = ""
        var worst: TimeInterval = 0
        for _ in 0..<20 {
            text += "今天"
            let start = Date()
            draft.content = text
            flush()
            let elapsed = Date().timeIntervalSince(start)
            worst = max(worst, elapsed)
        }
        report.append(("⑧ 弹窗内逐字输入（单次最差）", worst))
        print(String(format: "  %-42@ %7.1f ms", "⑧ 弹窗内逐字输入（单次最差）" as NSString, worst * 1000))
    }

    /// 切换创作弹窗的五种形态：每次都要换掉整棵表单子树
    func test03_ComposerKindSwitchCost() throws {
        seed()
        let appState = AppState.shared
        let size = CGSize(width: 760, height: 660)

        var worst: TimeInterval = 0
        var worstKind = ""
        for kind in ["life", "travel", "project", "wish", "transaction"] {
            let modal = NewEntryModal(
                appState: appState,
                initialKind: kind,
                initialProjectId: nil,
                initialCityCode: nil,
                initialCityName: nil
            ) { }
            let start = Date()
            mount(modal, size: size)
            flush()
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > worst { worst = elapsed; worstKind = kind }
        }
        report.append(("⑨ 切换创作形态（最慢一种）", worst))
        print(String(format: "  %-42@ %7.1f ms  (%@)",
                     "⑨ 切换创作形态（最慢一种）" as NSString, worst * 1000, worstKind as NSString))
    }

    /// 时间流滚动：翻页/换筛选会重排整列卡片
    func test04_TimelineScrollCost() throws {
        seed()
        let appState = AppState.shared
        let size = CGSize(width: 1280, height: 820)
        mount(StreamView(appState: appState), size: size)
        flush()

        // 模拟「滚到底再滚回来」：SwiftUI 的 LazyVStack 会重新物化卡片
        var worst: TimeInterval = 0
        for round in 0..<5 {
            let start = Date()
            // 改动一个会影响卡片内容的状态 → 触发整列重算
            appState.entries[round].content = appState.entries[round].content + " ·"
            flush()
            worst = max(worst, Date().timeIntervalSince(start))
        }
        report.append(("⑩ 时间流滚动重排（单次最差）", worst))
        print(String(format: "  %-42@ %7.1f ms", "⑩ 时间流滚动重排（单次最差）" as NSString, worst * 1000))
    }
}
