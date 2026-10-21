import SwiftUI

/// 账本流水修订弹窗 (EditTransactionSheet)
/// 从 LedgerAssetsView 中拆出的独立 Sheet 组件：
/// 负责单笔流水的收支类型 / 金额 / 类目 / 支付方式 / 属地城市 / 发生时间修订与保存。
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

// MARK: - 独立弹窗组件：修订流水 (EditTransactionSheet)

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
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            Text("修订流水账目")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

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
                        category = appState.incomeCategories.first ?? "薪资"
                    }
                }

                HStack(spacing: ArchiveSpacing.xs) {
                    Text("¥")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    TextField("0.00", text: $amountYuan)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                        .frame(minWidth: 80, idealWidth: 120, maxWidth: 160)
                }
                .padding(.horizontal, ArchiveSpacing.s)
                .padding(.vertical, 5)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            }

            TextField("账目名称", text: $title)
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
                HStack(spacing: 6) {
                    ForEach(appState.paymentMethods, id: \.self) { pay in
                        PaperPillButton(title: pay, isSelected: paymentMethod == pay) { paymentMethod = pay }
                    }
                }
            }

            HStack(spacing: ArchiveSpacing.s) {
                PaperDateTimePicker(selection: $occurredDate, label: "发生时间", showQuickShortcuts: true)
                Spacer()
                PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName, placeholder: "属地城市")
            }

            TextField("备注", text: $note)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存修订") {
                    saveChanges()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(isSubmitting || (FormatUtils.parseYuanToCents(amountYuan) ?? 0) <= 0)
            }
        }
        .padding(20)
        .frame(
            minWidth: ArchiveSheetWidth.standard,
            idealWidth: ArchiveSheetWidth.standard,
            maxWidth: ArchiveSheetWidth.standard
        )
        .background(ArchivePalette.archivePaper)
    }

    private func saveChanges() {
        guard let cents = FormatUtils.parseYuanToCents(amountYuan), cents > 0 else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateTransactionRequest(
                    amount: cents,
                    type: type,
                    category: category,
                    title: title.isEmpty ? category : title,
                    note: note.isEmpty ? nil : note,
                    paymentMethod: paymentMethod,
                    cityCode: cityCode.isEmpty ? nil : cityCode,
                    occurredAt: FormatUtils.beijingISOString(from: occurredDate),
                    // 关键：**透传原有的分期字段**。
                    // 原先这里完全没传，于是 `isInstallment` 取默认值 false，
                    // 而 `Bool` 一定会被 JSONEncoder 写进请求体 ——
                    // 后端据此把 `tx.IsInstallment = false`，
                    // 于是**任何一次编辑（哪怕只改个标题）都会把分期账目
                    // 降级成一次性支出**：分期负债凭空消失、流动余额被整额冲减。
                    // 用户全程只在界面上看到「改了笔备注」。
                    // 传**原始的可选值**（nil = 本次未携带 → 后端保持原值），
                    // 而不是强转成 true/false —— 后者的语义是「显式降级」。
                    isInstallment: transaction.isInstallment,
                    installmentChannelCode: transaction.installmentChannelCode,
                    installmentTotalAmount: transaction.installmentTotalAmount,
                    installmentMonths: transaction.installmentMonths,
                    // 月供：金额变了要按新总额重算；没变就沿用原值
                    installmentMonthlyPay: cents == transaction.amount
                        ? transaction.installmentMonthlyPay
                        : (cents / Int64(max(1, transaction.installmentMonths ?? 1))),
                    installmentRemainMonths: transaction.installmentRemainMonths,
                    repaymentDay: transaction.repaymentDay
                )
                _ = try await APIClient.shared.updateTransaction(id: transaction.id, req)
                // 账目在时间流里是合成条目，账目变了时间流也要跟着变
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
