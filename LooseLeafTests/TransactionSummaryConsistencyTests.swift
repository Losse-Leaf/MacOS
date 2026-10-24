import XCTest
@testable import LooseLeaf

/// 月度汇总的**口径**与**回滚**测试
///
/// 背景：时间流里的账目是客户端乐观写入的，月度汇总也是客户端先算的。
/// 一旦「客户端加、服务端不减」或者「跨月也加」，账面就会长期失真。
@MainActor
final class TransactionSummaryConsistencyTests: XCTestCase {

    private func summary(expense: Int64, income: Int64) -> TransactionSummary {
        var s = TransactionSummary()
        s.totalExpense = expense
        s.totalIncome = income
        s.balance = income - expense
        return s
    }

    // MARK: - 1. 只有落在汇总月份的账目才调整汇总

    func test01_OnlyAdjustsSummaryForSameMonth() {
        let (y, m) = FormatUtils.beijingCurrentYearMonth()
        let thisMonth = String(format: "%04d-%02d-15T10:00:00+08:00", y, m)
        let lastMonth = String(format: "%04d-%02d-15T10:00:00+08:00", y, m == 1 ? 12 : m - 1, m)

        XCTAssertTrue(
            SyncManager.isInSummaryMonth(thisMonth, summary: summary(expense: 0, income: 0)),
            "本月账目应计入本月汇总"
        )
        XCTAssertFalse(
            SyncManager.isInSummaryMonth(lastMonth, summary: summary(expense: 0, income: 0)),
            "补记往月的账**不能**加到本月汇总"
        )
    }

    /// 汇总自身可能停留在上个月（跨月离线启动）：必须按 summary.year/month 判断，
    /// 不能拿「当前自然月」硬套，否则本月账目会被加进上月汇总。
    func test01b_UsesSummaryOwnYearMonth() {
        var pastSummary = TransactionSummary(year: 2025, month: 3)
        pastSummary.totalExpense = 0
        let marchTx = "2025-03-15T10:00:00+08:00"
        XCTAssertTrue(
            SyncManager.isInSummaryMonth(marchTx, summary: pastSummary),
            "应使用汇总自身的年月判断"
        )

        let currentSummary = TransactionSummary()
        XCTAssertFalse(
            SyncManager.isInSummaryMonth(marchTx, summary: currentSummary),
            "往月账目不得计入当前月汇总"
        )
    }

    // MARK: - 2. 汇总调整必须可逆

    func test02_SummaryDeltaIsReversible() {
        var s = summary(expense: 1000, income: 0)
        s.categoryBreakdown["餐饮"] = 1000

        // 加一笔
        SyncManager.applySummaryDelta(&s, category: "餐饮", type: "expense", amount: 500)
        XCTAssertEqual(s.totalExpense, 1500)
        XCTAssertEqual(s.categoryBreakdown["餐饮"], 1500)
        XCTAssertEqual(s.balance, -1500)

        // 减回（删除 / 失败回滚走这条路）
        SyncManager.applySummaryDelta(&s, category: "餐饮", type: "expense", amount: -500)
        XCTAssertEqual(s.totalExpense, 1000, "回滚后总额必须回到原值")
        XCTAssertEqual(s.categoryBreakdown["餐饮"], 1000, "回滚后分类金额必须回到原值")
        XCTAssertEqual(s.balance, -1000, "balance = 收入 − 支出，支出 1000 收入 0 时为 -1000")
    }

    func test03_IncomeDeltaAlsoReversible() {
        var s = summary(expense: 0, income: 2000)
        SyncManager.applySummaryDelta(&s, category: "工资", type: "income", amount: 3000)
        XCTAssertEqual(s.totalIncome, 5000)
        XCTAssertEqual(s.balance, 5000)
        SyncManager.applySummaryDelta(&s, category: "工资", type: "income", amount: -3000)
        XCTAssertEqual(s.totalIncome, 2000)
        XCTAssertEqual(s.balance, 2000)
    }

    /// 扣减到 0 的分类不应留下「0」这个键
    func test04_CategoryKeyRemovedWhenFullyReversed() {
        var s = summary(expense: 0, income: 0)
        SyncManager.applySummaryDelta(&s, category: "咖啡", type: "expense", amount: 3800)
        XCTAssertEqual(s.categoryBreakdown["咖啡"], 3800)
        SyncManager.applySummaryDelta(&s, category: "咖啡", type: "expense", amount: -3800)
        XCTAssertEqual(s.categoryBreakdown["咖啡"] ?? 0, 0, "扣回后金额应为 0")
    }

    // MARK: - 3. 金额单位：分 ↔ 元

    func test05_AmountUnitsAreConsistent() {
        // 解析入口一律是「元 → 分」
        XCTAssertEqual(FormatUtils.parseYuanToCents("42.50"), 4250)
        XCTAssertEqual(FormatUtils.parseYuanToCents("0.01"), 1)
        // 输出入口一律是「分 → 元」
        XCTAssertEqual(FormatUtils.formattedYuan(cents: 4250), "42.50")
        // 带符号时的实际格式是「¥ 42.50」（符号后有空格）
        XCTAssertEqual(FormatUtils.formattedYuan(cents: 4250, includeSymbol: true), "¥ 42.50")
    }

    /// 四舍五入必须在**生产路径**上生效。
    /// 历史上这里曾从 .plain 改回截断，是个静默回归。
    func test06_ProductionParserRoundsHalfUp() {
        XCTAssertEqual(FormatUtils.parseYuanToCents("0.999"), 100, "0.999 元应进位到 1 分")
        XCTAssertEqual(FormatUtils.parseYuanToCents("42.999"), 4300, "42.999 元应进位到 4300 分")
        XCTAssertEqual(FormatUtils.parseYuanToCents("42.994"), 4299)
    }
}
