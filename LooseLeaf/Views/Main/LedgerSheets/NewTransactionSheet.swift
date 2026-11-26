import SwiftUI

/// 新建账目可视化表单弹窗 (NewTransactionSheet)
/// 承接从流水区抽离的完整收支录入与分期配置表单，复用 `PaperSheetScaffold` 与 `CreditChannelInstallmentSection`。
@MainActor
public struct NewTransactionSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var formType: String = "expense"
    @State private var formAmountYuan: String = ""
    @State private var formTitle: String = ""
    @State private var formCategory: String
    @State private var formPaymentMethod: String
    @State private var formNote: String = ""
    @State private var formOccurredAt: Date = Date()
    @State private var formIsInstallment: Bool = false
    @State private var formInstallmentChannelCode: String = ""
    @State private var formInstallmentMonths: Int = 12
    @State private var isSubmittingTx: Bool = false
    @State private var errorText: String?

    @FocusState private var isAmountFocused: Bool

    public init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
        _formCategory = State(initialValue: appState.expenseCategories.first ?? "餐饮")
        _formPaymentMethod = State(initialValue: appState.paymentMethods.first ?? "微信支付")
        if let firstCh = appState.creditChannels.first {
            _formInstallmentChannelCode = State(initialValue: firstCh.code)
        }
    }

    private var availableCreditChannels: [CreditChannel] {
        appState.creditChannels
    }

    private var parsedAmountCents: Int64 {
        FormatUtils.parseYuanToCents(formAmountYuan) ?? 0
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "记一笔账目",
            subtitle: "支持自定义类目、支付方式与分期账期配置",
            width: ArchiveSheetWidth.standard,
            isSubmitting: isSubmittingTx,
            isSubmitDisabled: parsedAmountCents <= 0 || (formType == "expense" && formIsInstallment && availableCreditChannels.isEmpty),
            submitTitle: "记入账本",
            onCancel: onDismiss,
            onSubmit: submitForm
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                HStack(spacing: ArchiveSpacing.s) {
                    PaperPillButton(title: "支出", isSelected: formType == "expense") {
                        formType = "expense"
                        if !appState.expenseCategories.contains(formCategory) {
                            formCategory = appState.expenseCategories.first ?? "餐饮"
                        }
                    }
                    PaperPillButton(title: "收入", isSelected: formType == "income") {
                        formType = "income"
                        if !appState.incomeCategories.contains(formCategory) {
                            formCategory = appState.incomeCategories.first ?? "工资收入"
                        }
                    }

                    HStack(spacing: ArchiveSpacing.xs) {
                        Text("¥")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        TextField("0.00", text: $formAmountYuan)
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.subheadline, weight: .semibold))
                            .focused($isAmountFocused)
                            .frame(minWidth: 80, idealWidth: 120, maxWidth: 160)
                            .accessibilityLabel("记账金额")
                    }
                    .padding(.horizontal, ArchiveSpacing.s)
                    .padding(.vertical, 5)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                TextField("账目说明", text: $formTitle)
                    .accessibilityLabel("账目说明")
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                VStack(alignment: .leading, spacing: 6) {
                    Text("类目选择")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    let availableCats = (formType == "income") ? appState.incomeCategories : appState.expenseCategories
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(availableCats, id: \.self) { cat in
                                PaperPillButton(title: cat, isSelected: formCategory == cat) {
                                    formCategory = cat
                                }
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
                                PaperPillButton(title: pay, isSelected: formPaymentMethod == pay) {
                                    formPaymentMethod = pay
                                }
                            }
                        }
                    }
                    .horizontalFadeMask()
                }

                if formType == "expense" {
                    CreditChannelInstallmentSection(
                        channels: availableCreditChannels,
                        hubURLString: appState.hubURLString,
                        isInstallment: $formIsInstallment,
                        channelCode: $formInstallmentChannelCode,
                        months: $formInstallmentMonths,
                        amountCents: parsedAmountCents
                    )
                }

                HStack(spacing: ArchiveSpacing.s) {
                    PaperDateTimePicker(selection: $formOccurredAt, label: "发生时间", showQuickShortcuts: true)
                    Spacer()
                }

                TextField("备注", text: $formNote)
                    .accessibilityLabel("账目备注")
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                if let errorText {
                    Text(errorText)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.footnote))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
            }
        }
        .onAppear {
            isAmountFocused = true
        }
    }

    private func submitForm() {
        guard let cents = FormatUtils.parseYuanToCents(formAmountYuan), cents > 0, !isSubmittingTx else { return }
        isSubmittingTx = true
        errorText = nil
        let cleanTitle = formTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? formCategory : cleanTitle
        let isInst = (formType == "expense" && formIsInstallment && !availableCreditChannels.isEmpty)
        let months = max(1, formInstallmentMonths)
        let monthlyPay = isInst ? (cents / Int64(months)) : nil
        let resolvedChannel = isInst
            ? (availableCreditChannels.first(where: { $0.code == formInstallmentChannelCode }) ?? availableCreditChannels.first)
            : nil

        Task { @MainActor in
            defer { isSubmittingTx = false }
            do {
                let req = CreateTransactionRequest(
                    amount: cents,
                    type: formType,
                    category: formCategory,
                    title: finalTitle,
                    note: formNote.isEmpty ? nil : formNote,
                    paymentMethod: appState.paymentMethods.contains(formPaymentMethod)
                        ? formPaymentMethod
                        : (appState.paymentMethods.first ?? formPaymentMethod),
                    occurredAt: FormatUtils.beijingISOString(from: formOccurredAt),
                    isInstallment: isInst,
                    installmentChannelCode: resolvedChannel?.code,
                    installmentTotalAmount: isInst ? cents : nil,
                    installmentMonths: isInst ? months : nil,
                    installmentMonthlyPay: monthlyPay,
                    installmentRemainMonths: isInst ? months : nil,
                    repaymentDay: resolvedChannel?.repaymentDay
                )
                _ = try await SyncManager.shared.submitTransaction(req)
                await appState.loadTransactions(forceFull: false)
                await appState.loadConfigAndProfile()
                appState.showTemporaryBanner("已记入账本：\(FormatUtils.formattedYuan(cents: cents, includeSymbol: true))")
                onDismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
