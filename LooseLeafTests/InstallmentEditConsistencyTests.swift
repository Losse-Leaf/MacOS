import XCTest
@testable import LooseLeaf

/// 编辑分期账目时，分期字段的一致性与三态契约（2026-10-22 修复）
///
/// 背景一：桌面端编辑分期账目时传的是**旧**的 `installmentTotalAmount`，
/// 而月供却按**新**金额重算 —— 于是库里
/// `amount = ¥6,000`、`installment_total_amount = ¥12,000`、`monthly_pay = ¥500`，
/// 资产大盘仍按 ¥12,000 计负债（实算 ¥11,500）。
/// 用户明明把金额改小了，**负债却纹丝不动**。
///
/// 背景二：桌面端原先**根本没有分期编辑 UI** —— 既不能改成分期，
/// 也不能取消分期；补上之后就必须遵守后端的三态契约：
/// 「取消分期」必须同时发 `is_installment: false` 与 `clear_installment: true`，
/// 单发 false 会被后端解读成「保持原值」，**取消不掉**。
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

    /// 造一笔**非**分期账目
    private func plainTransaction() -> Transaction {
        Transaction(
            id: 2,
            amount: 29_990,
            type: "expense",
            category: "数码器材",
            title: "iQOO",
            occurredAt: "2026-10-01T10:00:00+08:00",
            isInstallment: false
        )
    }

    // MARK: - 意图推导

    func test01_IntentDerivation() {
        let installment = installmentTransaction()
        let plain = plainTransaction()

        XCTAssertEqual(
            InstallmentEditing.intent(wantsInstallment: true, touched: true, isExpense: true, transaction: installment),
            .apply,
            "勾选分期 ⇒ 明确是分期"
        )
        XCTAssertEqual(
            InstallmentEditing.intent(wantsInstallment: false, touched: true, isExpense: true, transaction: installment),
            .cancel,
            "原本是分期且用户取消勾选 ⇒ 显式取消"
        )
        XCTAssertEqual(
            InstallmentEditing.intent(wantsInstallment: false, touched: true, isExpense: true, transaction: plain),
            .untouched,
            "原本不是分期且用户勾了又取消 ⇒ 本次与分期无关（无中生有 nothing to clear）"
        )
    }

    /// 关键：**没动过就不许改**
    ///
    /// 若只看「开关当前值 vs 原值」，那么「支出 → 收入 → 支出」这种来回切换
    /// 会被误判成「用户取消了分期」，一次无心的类型切换就把分期静默抹掉。
    func test02_UntouchedToggleNeverChangesInstallment() {
        let installment = installmentTransaction()
        XCTAssertEqual(
            InstallmentEditing.intent(wantsInstallment: false, touched: false, isExpense: true, transaction: installment),
            .untouched,
            "用户没动过分期开关（哪怕开关值与原值不同）⇒ 本次不涉及分期"
        )
        XCTAssertEqual(
            InstallmentEditing.intent(wantsInstallment: true, touched: false, isExpense: true, transaction: installment),
            .untouched,
            "没动过就不算「明确是分期」"
        )
    }

    /// 关键：切换收支类型**不得**销毁已有的分期
    func test03_TypeSwitchDoesNotCancelInstallment() {
        let installment = installmentTransaction()
        // 支出 → 收入：收入没有分期，但类型切换不是「取消」的意图
        XCTAssertEqual(
            InstallmentEditing.intent(wantsInstallment: true, touched: false, isExpense: false, transaction: installment),
            .untouched,
            "切到收入不得顺手取消分期 —— 一次无心的类型切换会静默抹掉账期与负债"
        )
    }

    /// 原账目是分期且用户没动开关时，**仍要带上账期字段** ——
    /// 否则后端进入「写分期」分支却不带总额，「金额改了、负债没改」又回来了。
    func test04_UntouchedStillCarriesInstallmentFields() {
        let fields = InstallmentEditing.fields(
            for: installmentTransaction(),
            newAmountCents: 600_000,
            intent: .untouched
        )
        XCTAssertEqual(
            fields.totalAmount, 600_000,
            "原账目是分期时，即便用户没动开关，总额也必须跟随新金额"
        )
        XCTAssertEqual(fields.monthlyPay, 50_000, "月供同理")
        XCTAssertFalse(fields.clearInstallment, "没动过就不许声明 clear_installment")
    }

    /// 原账目**不是**分期时，什么都不带（服务端保持原值）
    func test05_UntouchedOnPlainTransactionCarriesNothing() {
        let fields = InstallmentEditing.fields(
            for: plainTransaction(),
            newAmountCents: 29_990,
            intent: .untouched
        )
        XCTAssertNil(fields.totalAmount, "非分期账目不该带账期字段")
        XCTAssertNil(fields.monthlyPay, "非分期账目不该带月供")
        XCTAssertFalse(fields.clearInstallment, "不得声明 clear_installment")
    }

    // MARK: - 取消分期必须带 clear_installment

    func test02_CancelCarriesClearInstallment() {
        let fields = InstallmentEditing.fields(
            for: installmentTransaction(),
            newAmountCents: 1_200_000,
            intent: .cancel
        )
        XCTAssertEqual(fields.isInstallment, false, "取消分期必须显式发 is_installment=false")
        XCTAssertTrue(fields.clearInstallment, "取消分期必须显式发 clear_installment=true")
        XCTAssertNil(fields.totalAmount, "取消分期不应再携带账期字段")
        XCTAssertNil(fields.monthlyPay, "取消分期不应再携带月供")
    }

    func test03_UntouchedDoesNotClear() {
        let fields = InstallmentEditing.fields(
            for: plainTransaction(),
            newAmountCents: 29_990,
            intent: .untouched
        )
        XCTAssertFalse(fields.clearInstallment, "本次与分期无关时不得声明 clear_installment")
    }

    // MARK: - 线格式：请求体里必须真的出现 clear_installment

    func test04_CancelRequestCarriesClearInstallmentOnTheWire() throws {
        let fields = InstallmentEditing.fields(
            for: installmentTransaction(),
            newAmountCents: 1_200_000,
            intent: .cancel
        )
        let req = CreateTransactionRequest(
            amount: 1_200_000,
            type: "expense",
            category: "数码器材",
            title: "分期显示器",
            occurredAt: "2026-10-01T10:00:00+08:00",
            isInstallment: fields.isInstallment,
            clearInstallment: fields.clearInstallment,
            installmentChannelCode: fields.channelCode,
            installmentTotalAmount: fields.totalAmount,
            installmentMonths: fields.months,
            installmentMonthlyPay: fields.monthlyPay,
            installmentRemainMonths: fields.remainMonths,
            repaymentDay: fields.repaymentDay
        )
        let json = String(data: try JSONEncoder().encode(req), encoding: .utf8) ?? ""
        XCTAssertTrue(
            json.contains("\"clear_installment\":true"),
            "请求体里必须出现 clear_installment=true，否则后端会保持原值、取消不掉。实际: \(json)"
        )
        XCTAssertTrue(
            json.contains("\"is_installment\":false"),
            "请求体里必须出现 is_installment=false。实际: \(json)"
        )
    }

    func test05_ApplyRequestDoesNotCarryClearInstallment() throws {
        let fields = InstallmentEditing.fields(
            for: installmentTransaction(),
            newAmountCents: 1_200_000,
            intent: .apply
        )
        let req = CreateTransactionRequest(
            amount: 1_200_000,
            type: "expense",
            category: "数码器材",
            title: "分期显示器",
            occurredAt: "2026-10-01T10:00:00+08:00",
            isInstallment: fields.isInstallment,
            clearInstallment: fields.clearInstallment
        )
        let json = String(data: try JSONEncoder().encode(req), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"is_installment\":true"), "保留分期必须发 is_installment=true")
        XCTAssertFalse(
            json.contains("\"clear_installment\":true"),
            "保留分期时不得出现 clear_installment=true，否则会被服务端误判成取消。实际: \(json)"
        )
    }

    func test06_NilIsInstallmentIsOmittedFromTheWire() throws {
        // isInstallment 为 nil 时必须**省略**该 key（Swift 的 encodeIfPresent 语义），
        // 这样服务端才拿不到该字段、保持原值。
        var req = CreateTransactionRequest(
            amount: 1,
            type: "expense",
            category: "x",
            title: "y",
            occurredAt: "2026-10-01T10:00:00+08:00"
        )
        req.isInstallment = nil
        let json = String(data: try JSONEncoder().encode(req), encoding: .utf8) ?? ""
        XCTAssertFalse(
            json.contains("\"is_installment\""),
            "is_installment 为 nil 时必须省略该字段。实际: \(json)"
        )
    }

    // MARK: - 金额与账期字段的自洽

    func test07_TotalAmountFollowsAmountChange() {
        let fields = InstallmentEditing.fields(
            for: installmentTransaction(),
            newAmountCents: 600_000,
            intent: .apply
        )
        XCTAssertEqual(
            fields.totalAmount, 600_000,
            "金额从 ¥12,000 改成 ¥6,000 后，分期总额必须同步成 ¥6,000 —— 否则资产大盘仍按旧总额计负债"
        )
    }

    func test08_MonthlyPayFollowsAmountChange() {
        let fields = InstallmentEditing.fields(
            for: installmentTransaction(),
            newAmountCents: 600_000,
            intent: .apply
        )
        XCTAssertEqual(
            fields.monthlyPay, 50_000,
            "月供必须按新金额重算（¥6,000 / 12 期 = ¥500）"
        )
    }

    func test09_TotalAndMonthlyPayStayConsistent() {
        let fields = InstallmentEditing.fields(
            for: installmentTransaction(),
            newAmountCents: 600_000,
            intent: .apply
        )
        let months = Int64(fields.months ?? 0)
        let monthly = Int64(fields.monthlyPay ?? 0)
        let total = Int64(fields.totalAmount ?? 0)

        XCTAssertGreaterThan(months, 0)
        XCTAssertEqual(
            monthly * months, total,
            "月供 × 期数必须等于分期总额（尾差按后端口径落最后一期）"
        )
    }

    func test10_UnchangedAmountKeepsOriginalTotal() {
        let tx = installmentTransaction()
        let fields = InstallmentEditing.fields(
            for: tx,
            newAmountCents: tx.amount,
            intent: .apply
        )
        XCTAssertEqual(fields.totalAmount, tx.installmentTotalAmount, "金额没改，总额应沿用原值")
    }

    func test11_TotalDifferentFromAmountIsPreserved() {
        var tx = installmentTransaction()
        // 例如：一笔 ¥2,000 的首付流水，分期总额却是 ¥12,000
        tx.amount = 200_000
        tx.installmentTotalAmount = 1_200_000

        let fields = InstallmentEditing.fields(
            for: tx,
            newAmountCents: tx.amount,
            intent: .apply
        )
        XCTAssertEqual(
            fields.totalAmount, 1_200_000,
            "总额与金额本就不同的账目，不得被顺手归一成金额"
        )
        XCTAssertEqual(
            fields.monthlyPay, 100_000,
            "月供必须按**总额**算（不是按金额），否则与后端口径分叉"
        )
    }

    func test12_ZeroMonthsDoesNotDivideByZero() {
        var tx = installmentTransaction()
        tx.installmentMonths = 0
        tx.installmentMonthlyPay = 0

        let fields = InstallmentEditing.fields(
            for: tx,
            newAmountCents: 600_000,
            intent: .apply,
            months: 0
        )
        XCTAssertNil(fields.monthlyPay, "期数为 0 时月供应为 nil，而不是崩溃或算出垃圾值")
        XCTAssertEqual(fields.totalAmount, 600_000, "总额仍应跟随金额")
    }

    func test13_ChangingMonthsRecomputesMonthlyPay() {
        let fields = InstallmentEditing.fields(
            for: installmentTransaction(),
            newAmountCents: 1_200_000,
            intent: .apply,
            months: 24
        )
        XCTAssertEqual(fields.months, 24, "期数应按用户选择")
        XCTAssertEqual(
            fields.monthlyPay, 50_000,
            "期数改了月供必须跟着重算（¥12,000 / 24 期 = ¥500）"
        )
    }
}
