import SwiftUI

/// 账本流水修订弹窗 (EditTransactionSheet)
/// 统一收口至 `PaperSheetScaffold`（带自适应 `ScrollView`，展开分期表单永不裁切底栏按钮），
/// 并修正 `DEC-09` 后空渠道引导文案为指向 Web 展厅后台。
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
    @State private var cityCode: String
    @State private var cityName: String
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
        _cityCode = State(initialValue: transaction.cityCode ?? "")
        let resolvedName = transaction.cityCode.flatMap { code in
            CityDictionary.standardCities.first(where: { $0.code == code })?.name
        } ?? ""
        _cityName = State(initialValue: resolvedName)
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

    private func normalizeInstallmentChannel() {
        guard let first = availableCreditChannels.first else { return }
        if !availableCreditChannels.contains(where: { $0.code == installmentChannelCode }) {
            installmentChannelCode = first.code
        }
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
                    PaperPillButton(title: "收入", isSelected: type == "income") {
                        type = "income"
                        if !appState.incomeCategories.contains(category) {
                            category = appState.incomeCategories.first ?? "工资收入"
                        }
                    }

                    HStack(spacing: ArchiveSpacing.xs) {
                        Text("¥")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        TextField("0.00", text: $amountYuan)
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                            .focused($isAmountFocused)
                            .frame(minWidth: 80, idealWidth: 120, maxWidth: 160)
                            .accessibilityLabel("账目金额")
                    }
                    .padding(.horizontal, ArchiveSpacing.s)
                    .padding(.vertical, 5)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
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
                    Toggle("分期付款", isOn: $wantsInstallment)
                        .toggleStyle(.paperCheckbox)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .disabled(availableCreditChannels.isEmpty)
                        .help(availableCreditChannels.isEmpty ? "请前往 Web 展厅后台「资产 → 渠道管理」配置分期渠道" : "")
                        .onChange(of: wantsInstallment) { _, isOn in
                            installmentTouched = true
                            if isOn { normalizeInstallmentChannel() }
                        }
                        .onChange(of: appState.creditChannels) { _, _ in
                            if wantsInstallment { normalizeInstallmentChannel() }
                        }

                    if availableCreditChannels.isEmpty {
                        HStack(spacing: 8) {
                            Text("请前往 Web 展厅后台「资产 → 渠道管理」配置分期渠道与每月还款日。")
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.inkMuted)
                            if let hubURL = URL(string: appState.hubURLString) {
                                Link("打开 Web 后台 ↗", destination: hubURL)
                                    .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                            }
                        }
                    }
                }

                if wantsInstallment && type == "expense" {
                    HStack(spacing: ArchiveSpacing.s) {
                        PaperSelect(
                            selection: $installmentChannelCode,
                            options: availableCreditChannels.map {
                                PaperSelectOption(value: $0.code, label: "\($0.name) (每月\($0.repaymentDay)日)")
                            },
                            label: "分期渠道："
                        )

                        PaperSelect(
                            selection: $installmentMonths,
                            options: ArchiveInstallmentOptions.installmentOptions.map {
                                PaperSelectOption(value: $0, label: "\($0) 期")
                            },
                            label: "期数："
                        )
                    }

                    if let channel = selectedCreditChannel {
                        Text("还款日跟随渠道：每月 \(channel.repaymentDay) 日")
                            .font(ArchiveTypography.monoScale(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    let cents = FormatUtils.parseYuanToCents(amountYuan) ?? 0
                    let validInstallment = cents > 0 && installmentMonths > 0
                    Text(validInstallment
                         ? "每期 ¥\(FormatUtils.formattedYuan(cents: cents / Int64(installmentMonths))) · 总额 ¥\(FormatUtils.formattedYuan(cents: cents))"
                         : "输入有效金额后自动核算每期应还")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .lineLimit(1)
                }

                if willCancelInstallment {
                    Text("保存后将取消分期：账期、期数、月供与渠道会被一并清空，负债相应减少。")
                        .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                HStack(spacing: ArchiveSpacing.s) {
                    PaperDateTimePicker(selection: $occurredDate, label: "发生时间", showQuickShortcuts: true)
                    Spacer()
                    PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName, placeholder: "属地城市")
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
        guard let cents = FormatUtils.parseYuanToCents(amountYuan), cents > 0, !isSubmitting else { return }
        let intent = InstallmentEditing.intent(
            wantsInstallment: wantsInstallment,
            touched: installmentTouched,
            isExpense: type == "expense",
            transaction: transaction
        )
        if intent == .apply && selectedCreditChannel == nil {
            errorText = "请先前往 Web 展厅后台「资产 → 渠道管理」配置并选择分期渠道"
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
                    type: type,
                    category: category,
                    title: title,
                    note: note,
                    paymentMethod: paymentMethod,
                    cityCode: cityCode.isEmpty ? nil : cityCode,
                    occurredAt: FormatUtils.beijingISOString(from: occurredDate),
                    isInstallment: installmentFields.isInstallment,
                    clearInstallment: installmentFields.clearInstallment,
                    installmentChannelCode: installmentFields.channelCode,
                    installmentTotalAmount: installmentFields.totalAmount,
                    installmentMonths: installmentFields.months,
                    installmentMonthlyPay: installmentFields.monthlyPay,
                    installmentRemainMonths: installmentFields.remainMonths,
                    repaymentDay: installmentFields.repaymentDay,
                    clearCity: cityCode.isEmpty ? true : nil
                )
                _ = try await APIClient.shared.updateTransaction(id: transaction.id, req)
                await appState.loadTransactionsAndAssets(forceFull: false)
                await appState.loadEntries(forceFull: false)
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
