import XCTest
@testable import LooseLeaf

/// 编辑分期账目时，分期字段的一致性（2026-10-22 修复）
///
/// 背景：桌面端编辑分期账目时传的是**旧**的 `installmentTotalAmount`，
/// 而月供却按**新**金额重算 —— 于是库里
/// `amount = ¥6,000`、`installment_total_amount = ¥12,000`、`monthly_pay = ¥500`，
/// 资产大盘仍按 ¥12,000 计负债（实算 ¥11,500）。
/// 用户明明把金额改小了，**负债却纹丝不动**，
/// 展厅与桌面端显示的「分期总额」也对不上。
///
/// 口径：**分期总额 == 账目金额**（与 Web / Android 一致）。
@MainActor
final class InstallmentEditConsistencyTests: XCTestCase {

    /// 造一笔 ¥12,000 / 12 期、月供 ¥1,000 的分期账目
    private func installmentTransaction(amount: Int64 = 1_200_000) -> Transaction {
        Transaction(
            id: 1,
            amount: amount,
            type: "expense",
            category: "数码器材",
            title: "分期显示器",
            occurredAt: "2026-10-01T10:00:00+08:00",
            isInstallment: true,
            installmentChannelCode: "huabei",
            installmentTotalAmount: amount,
            installmentMonths: 12,
            installmentMonthlyPay: amount / 12,
            installmentRemainMonths: 11,
            repaymentDay: 10
        )
    }

    /// 关键：金额改了，**分期总额必须跟着改**
    func test01_TotalAmountFollowsAmountChange() {
        let tx = installmentTransaction()
        let fields = InstallmentEditing.fields(for: tx, newAmountCents: 600_000)

        XCTAssertEqual(
            fields.totalAmount, 600_000,
            "金额从 ¥12,000 改成 ¥6,000 后，分期总额必须同步成 ¥6,000 —— 否则资产大盘仍按旧总额计负债"
        )
    }

    /// 关键：金额改了，月供必须跟着改
    func test02_MonthlyPayFollowsAmountChange() {
        let tx = installmentTransaction()
        let fields = InstallmentEditing.fields(for: tx, newAmountCents: 600_000)

        XCTAssertEqual(
            fields.monthlyPay, 50_000,
            "月供必须按新金额重算（¥6,000 / 12 期 = ¥500）"
        )
    }

    /// 关键：总额与月供**必须自洽** —— 月供 × 期数 ≈ 总额
    ///
    /// 这条是整组缺陷的判据：原先「总额=旧值、月供=新值」两者互相矛盾。
    func test03_TotalAndMonthlyPayStayConsistent() {
        let tx = installmentTransaction()
        let newAmount: Int64 = 600_000
        let fields = InstallmentEditing.fields(for: tx, newAmountCents: newAmount)

        let months = Int64(fields.months ?? 0)
        let monthly = Int64(fields.monthlyPay ?? 0)
        let total = Int64(fields.totalAmount ?? 0)

        XCTAssertGreaterThan(months, 0)
        XCTAssertEqual(
            monthly * months, total,
            "月供 × 期数必须等于分期总额（尾差按后端口径落最后一期）"
        )
    }

    /// 金额没改时**沿用原值** —— 总额可能本就与金额不同（例如「首付 + 分期」）
    func test04_UnchangedAmountKeepsOriginalFields() {
        let tx = installmentTransaction()
        let fields = InstallmentEditing.fields(for: tx, newAmountCents: tx.amount)

        XCTAssertEqual(fields.totalAmount, tx.installmentTotalAmount, "金额没改，总额应沿用原值")
        XCTAssertEqual(fields.monthlyPay, tx.installmentMonthlyPay, "金额没改，月供应沿用原值")
    }

    /// 金额没改但总额本就与金额不同 —— 不得被「顺手归一」成金额
    func test05_TotalDifferentFromAmountIsPreserved() {
        var tx = installmentTransaction()
        // 例如：一笔 ¥2,000 的首付流水，分期总额却是 ¥12,000
        tx.amount = 200_000
        tx.installmentTotalAmount = 1_200_000

        let fields = InstallmentEditing.fields(for: tx, newAmountCents: tx.amount)
        XCTAssertEqual(
            fields.totalAmount, 1_200_000,
            "总额与金额本就不同的账目，编辑其它字段时不得被改写"
        )
    }

    /// 期数为 0 的畸形账目不得做除零
    func test06_ZeroMonthsDoesNotDivideByZero() {
        var tx = installmentTransaction()
        tx.installmentMonths = 0
        tx.installmentMonthlyPay = 0

        let fields = InstallmentEditing.fields(for: tx, newAmountCents: 600_000)
        XCTAssertNil(fields.monthlyPay, "期数为 0 时月供应为 nil，而不是崩溃或算出垃圾值")
        XCTAssertEqual(fields.totalAmount, 600_000, "总额仍应跟随金额")
    }
}
