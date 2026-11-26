import SwiftUI

/// 账本流水修订弹窗 (EditTransactionSheet)
/// 统一收口至 `PaperSheetScaffold` 与共享 `CreditChannelInstallmentSection` 分期配置区。
@MainActor
public struct EditTransactionSheet: View {
    @Bindable var appState: AppState
    let transaction: Transaction
    var onDismiss: () -> Void

    @State private var type: String
    @State private var amountYuan: String
    @State private var title: String
    @State private var category: String
    @State private var paymentMethod: String
    @State private var note: String
    @State private var occurredDate: Date
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    @State private var wantsInstallment: Bool
    @State private var installmentTouched: Bool = false
    @State private var installmentChannelCode: String
    @State private var installmentMonths: Int

    @FocusState private var isAmountFocused: Bool

    public init(appState: AppState, transaction: Transaction, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.transaction = transaction
        self.onDismiss = onDismiss
        _type = State(initialValue: transaction.type)
        _amountYuan = State(initialValue: FormatUtils.formattedYuan(cents: transaction.amount))
        _title = State(initialValue: transaction.title)
        _category = State(initialValue: transaction.category)
        _paymentMethod = State(initialValue: transaction.paymentMethod ?? appState.paymentMethods.first ?? "微信支付")
        _note = State(initialValue: transaction.note ?? "")
        _occurredDate = State(initialValue: FormatUtils.parseFlexDate(transaction.occurredAt) ?? Date())
        _wantsInstallment = State(initialValue: transaction.isInstallment == true)
        _installmentChannelCode = State(initialValue: transaction.installmentChannelCode ?? "")
        _installmentMonths = State(initialValue: transaction.installmentMonths ?? 12)
    }

    private var availableCreditChannels: [CreditChannel] {
        appState.creditChannels
    }

    private var selectedCreditChannel: CreditChannel? {
        availableCreditChannels.first { $0.code == installmentChannelCode }
    }

    private var willCancelInstallment: Bool {
        guard transaction.isInstallment == true else { return false }
        if type != "expense" { return true }
        return installmentTouched && !wantsInstallment
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "修订流水账目",
            width: ArchiveSheetWidth.standard,
            isSubmitting: isSubmitting,
            isSubmitDisabled: (FormatUtils.parseYuanToCents(amountYuan) ?? 0) <= 0,
            submitTitle: "保存修订",
            onCancel: onDismiss,
            onSubmit: saveChanges
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                HStack(spacing: ArchiveSpacing.s) {
                    PaperPillButton(title: "支出", isSelected: type == "expense") {
                        type = "expense"
                        if !appState.expenseCategories.contains(category) {
                            category = appState.expenseCategories.first ?? "餐饮"
                        }
                    }
                    .disabled(transaction.isInstallmentRepayment)

                    PaperPillButton(title: "收入", isSelected: type == "income") {
                        type = "income"
                        if !appState.incomeCategories.contains(category) {
                            category = appState.incomeCategories.first ?? "工资收入"
                        }
                    }
                    .disabled(transaction.isInstallmentRepayment)

                    HStack(spacing: ArchiveSpacing.xs) {
                        Text("¥")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        TextField("0.00", text: $amountYuan)
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                            .focused($isAmountFocused)
                            .disabled(transaction.isInstallmentRepayment)
                            .frame(minWidth: 80, idealWidth: 120, maxWidth: 160)
                            .accessibilityLabel("账目金额")
                    }
                    .padding(.horizontal, ArchiveSpacing.s)
                    .padding(.vertical, 5)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .opacity(transaction.isInstallmentRepayment ? 0.65 : 1.0)
                }

                if transaction.isInstallmentRepayment {
                    Text("分期还款账目金额不可直接修改；如需变动请在 Web 端分期计划中撤销还款后重新标记。")
                        .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                TextField("账目名称", text: $title)
                    .accessibilityLabel("账目名称")
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                VStack(alignment: .leading, spacing: 6) {
                    Text("类目选择")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    let availableCats = (type == "income") ? appState.incomeCategories : appState.expenseCategories
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(availableCats, id: \.self) { cat in
                                PaperPillButton(title: cat, isSelected: category == cat) { category = cat }
                            }
                        }
                    }
                    .horizontalFadeMask()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("支付方式")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(appState.paymentMethods, id: \.self) { pay in
                                PaperPillButton(title: pay, isSelected: paymentMethod == pay) { paymentMethod = pay }
                            }
                        }
                    }
                }

                if type == "expense" {
                    CreditChannelInstallmentSection(
                        channels: availableCreditChannels,
                        hubURLString: appState.hubURLString,
                        isInstallment: $wantsInstallment,
                        channelCode: $installmentChannelCode,
                        months: $installmentMonths,
                        amountCents: FormatUtils.parseYuanToCents(amountYuan) ?? 0,
                        onToggleChanged: { _ in installmentTouched = true }
                    )
                }

                if willCancelInstallment {
                    Text("保存后将取消分期：账期、期数、月供与渠道会被一并清空，负债相应减少。")
                        .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                HStack(spacing: ArchiveSpacing.s) {
                    PaperDateTimePicker(selection: $occurredDate, label: "发生时间", showQuickShortcuts: true)
                    Spacer()
                }

                TextField("备注", text: $note)
                    .accessibilityLabel("备注")
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                if let errorText {
                    Text(errorText)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
            }
        }
        .onAppear {
            isAmountFocused = true
        }
    }

    private func saveChanges() {
        guard let parsedCents = FormatUtils.parseYuanToCents(amountYuan), !isSubmitting else { return }
        let cents = transaction.isInstallmentRepayment ? transaction.amount : parsedCents
        let effectiveType = transaction.isInstallmentRepayment ? transaction.type : type
        guard cents > 0 else { return }
        let intent = InstallmentEditing.intent(
            wantsInstallment: wantsInstallment,
            touched: installmentTouched,
            isExpense: effectiveType == "expense",
            transaction: transaction
        )
        if intent == .apply && selectedCreditChannel == nil {
            errorText = "请先前往 Web 管理端「资产 → 渠道管理」配置并选择分期渠道"
            return
        }
        let installmentFields = InstallmentEditing.fields(
            for: transaction,
            newAmountCents: cents,
            intent: intent,
            channelCode: installmentChannelCode,
            months: installmentMonths,
            repaymentDay: selectedCreditChannel?.repaymentDay
        )
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateTransactionRequest(
                    amount: cents,
                    type: effectiveType,
                    category: category,
                    title: title,
                    note: note,
                    paymentMethod: paymentMethod,
                    occurredAt: FormatUtils.beijingISOString(from: occurredDate),
                    isInstallment: installmentFields.isInstallment,
                    clearInstallment: installmentFields.clearInstallment,
                    installmentChannelCode: installmentFields.channelCode,
                    installmentTotalAmount: installmentFields.totalAmount,
                    installmentMonths: installmentFields.months,
                    installmentMonthlyPay: installmentFields.monthlyPay,
                    installmentRemainMonths: installmentFields.remainMonths,
                    repaymentDay: installmentFields.repaymentDay
                )
                _ = try await APIClient.shared.updateTransaction(id: transaction.id, req)
                await appState.loadTransactions(forceFull: false)
                await appState.loadEntries(forceFull: false)
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
