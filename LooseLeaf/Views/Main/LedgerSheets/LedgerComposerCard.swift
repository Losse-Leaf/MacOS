import SwiftUI

/// 独立抽离的双模记账控制台（隔离输入态，杜绝每次敲击字符触发父级数千条账目重筛与重排）
@MainActor
struct LedgerComposerCard: View {
    @Bindable var appState: AppState
    @Binding var showVisualForm: Bool
    @Binding var errorNotice: String?

    @State private var quickLine: String = ""
    @State private var formType: String = "expense"
    @State private var formAmountYuan: String = ""
    @State private var formTitle: String = ""
    @State private var formCategory: String = "餐饮"
    @State private var formPaymentMethod: String
    @State private var formNote: String = ""
    @State private var formOccurredAt: Date = Date()
    @State private var formIsInstallment: Bool = false
    @State private var formInstallmentChannelCode: String = ""
    @State private var formInstallmentMonths: Int = 12
    @State private var isSubmittingTx: Bool = false

    init(
        appState: AppState,
        showVisualForm: Binding<Bool>,
        errorNotice: Binding<String?>
    ) {
        self.appState = appState
        self._showVisualForm = showVisualForm
        self._errorNotice = errorNotice
        self._formPaymentMethod = State(initialValue: appState.paymentMethods.first ?? "微信支付")
        if let firstCh = appState.creditChannels.first {
            self._formInstallmentChannelCode = State(initialValue: firstCh.code)
        }
    }

    private var availableCreditChannels: [CreditChannel] {
        appState.creditChannels
    }

    private var quickParsed: FormatUtils.QuickLedgerParsed? {
        let isIncome = quickLine.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+")
        return FormatUtils.parseQuickLedgerInput(
            quickLine,
            knownCategories: isIncome ? appState.incomeCategories : appState.expenseCategories
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            HStack(spacing: 10) {
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 14))
                    .foregroundStyle(ArchivePalette.accentWarm)

                TextField("快速记账（如：42.5 咖啡）…", text: $quickLine)
                    .accessibilityLabel("快速记账输入")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .onSubmit {
                        submitQuickLine()
                    }

                Text(quickParsed.map { "\($0.category) · \(FormatUtils.formattedYuan(cents: $0.amountCents, includeSymbol: true))" } ?? "输入金额与摘要自动识别")
                    .font(ArchiveTypography.monoScale(size: 11.5, weight: .medium))
                    .foregroundStyle(quickParsed != nil ? ArchivePalette.accentWarm : ArchivePalette.inkMuted.opacity(0.65))
                    .lineLimit(1)
                    .frame(width: 148, alignment: .trailing)

                Button {
                    submitQuickLine()
                } label: {
                    if isSubmittingTx {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("记入账本")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
                .disabled(isSubmittingTx || quickParsed == nil)

                Button {
                    withAnimation(ArchiveMotion.standard) {
                        showVisualForm.toggle()
                    }
                } label: {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Image(systemName: showVisualForm ? "chevron.up.circle.fill" : "slider.horizontal.below.rectangle")
                        Text(showVisualForm ? "收起表单" : "可视化表单")
                    }
                    .font(ArchiveTypography.bodySans(size: 11.5))
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
            }

            if showVisualForm {
                Divider().overlay(ArchivePalette.borderDivider)

                VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                    HStack(spacing: ArchiveSpacing.m) {
                        HStack(spacing: ArchiveSpacing.xs) {
                            PaperPillButton(title: "支出", isSelected: formType == "expense") {
                                formType = "expense"
                                if !appState.expenseCategories.contains(formCategory) {
                                    formCategory = appState.expenseCategories.first ?? "餐饮"
                                }
                            }
                            PaperPillButton(title: "收入", isSelected: formType == "income") {
                                formType = "income"
                                if !appState.incomeCategories.contains(formCategory) {
                                    formCategory = appState.incomeCategories.first ?? "薪资"
                                }
                            }
                        }

                        HStack(spacing: ArchiveSpacing.xs) {
                            Text("¥")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkMuted)
                            TextField("0.00", text: $formAmountYuan)
                                .accessibilityLabel("记账金额")
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.monoScale(size: 13.5, weight: .semibold))
                                .frame(width: 140)
                        }
                        .padding(.horizontal, ArchiveSpacing.s)
                        .padding(.vertical, 5)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                        .overlay(
                            RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                        )

                        TextField("账目说明", text: $formTitle)
                            .accessibilityLabel("账目说明")
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.bodySans(size: 12.5))
                            .padding(.horizontal, ArchiveSpacing.s)
                            .padding(.vertical, 5)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                            )
                    }

                    HStack(alignment: .top, spacing: ArchiveSpacing.s) {
                        Text("类目：")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(.top, 4)

                        let categoriesToShow = (formType == "income") ? appState.incomeCategories : appState.expenseCategories
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(categoriesToShow, id: \.self) { cat in
                                    PaperPillButton(title: cat, isSelected: formCategory == cat) {
                                        formCategory = cat
                                    }
                                }
                            }
                        }
                        .horizontalFadeMask()
                    }

                    HStack(spacing: ArchiveSpacing.s) {
                        Text("支付：")
                            .font(ArchiveTypography.bodySans(size: 11.5))
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

                        Spacer()

                        if formType == "expense" {
                            Toggle("分期付款", isOn: $formIsInstallment)
                                .toggleStyle(.paperCheckbox)
                                .font(ArchiveTypography.bodySans(size: 11.5))
                                .onChange(of: formIsInstallment) { _, isOn in
                                    if isOn, formInstallmentChannelCode.isEmpty, let first = availableCreditChannels.first {
                                        formInstallmentChannelCode = first.code
                                    }
                                }
                        }
                    }

                    HStack(spacing: 10) {
                        Text("时间：")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)

                        PaperDatePicker(selection: $formOccurredAt)
                        PaperTimePicker(selection: $formOccurredAt)

                        Spacer()
                    }

                    if formIsInstallment && formType == "expense" {
                        CreditChannelInstallmentSection(
                            channels: availableCreditChannels,
                            hubURLString: appState.hubURLString,
                            isInstallment: $formIsInstallment,
                            channelCode: $formInstallmentChannelCode,
                            months: $formInstallmentMonths,
                            amountCents: FormatUtils.parseYuanToCents(formAmountYuan) ?? 0,
                            showToggle: false,
                            showEmptyHint: true,
                            showCardChrome: true
                        )
                    }

                    HStack {
                        TextField("备注", text: $formNote)
                            .accessibilityLabel("账目备注")
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                        Button {
                            submitVisualForm()
                        } label: {
                            if isSubmittingTx {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("完成记账并入账")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                        .paperButtonFocusRing()
                        .disabled(
                            isSubmittingTx
                                || (FormatUtils.parseYuanToCents(formAmountYuan) ?? 0) <= 0
                                || (formType == "expense" && formIsInstallment && availableCreditChannels.isEmpty)
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(ArchiveCardMetrics.padding)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
    }

    private func submitQuickLine() {
        guard let parsed = quickParsed, !isSubmittingTx else { return }
        isSubmittingTx = true
        errorNotice = nil
        Task { @MainActor in
            defer { isSubmittingTx = false }
            do {
                _ = try await appState.submitQuickLedger(
                    amountCents: parsed.amountCents,
                    type: parsed.type,
                    category: parsed.category,
                    title: parsed.title
                )
                quickLine = ""
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }

    private func submitVisualForm() {
        guard let cents = FormatUtils.parseYuanToCents(formAmountYuan), cents > 0, !isSubmittingTx else { return }
        isSubmittingTx = true
        errorNotice = nil
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
                formAmountYuan = ""
                formTitle = ""
                formNote = ""
                formOccurredAt = Date()
                formIsInstallment = false
                await appState.loadTransactions(forceFull: false)
                await appState.loadConfigAndProfile()
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }
}
