import SwiftUI

/// 添置随身设备弹窗 (AddGearSheet)
/// 统一收口至 `PaperSheetScaffold` 与共享 `CreditChannelInstallmentSection` 分期配置区。
@MainActor
public struct AddGearSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var name: String = ""
    @State private var spec: String = ""
    @State private var category: String = "数码器材"
    @State private var priceYuan: String = ""
    @State private var note: String = ""
    @State private var createTransaction: Bool = true
    @State private var paymentMethod: String = "微信支付"
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    @State private var purchaseDate: Date = Date()
    @State private var isInstallment: Bool = false
    @State private var installmentChannelCode: String = ""
    @State private var installmentMonths: Int = 12

    @FocusState private var isNameFocused: Bool

    public init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
        _paymentMethod = State(initialValue: appState.paymentMethods.first ?? "微信支付")
        _installmentChannelCode = State(initialValue: appState.creditChannels.first?.code ?? "")
        _category = State(initialValue: appState.gearCategories.first ?? "数码器材")
    }

    private var selectedCreditChannel: CreditChannel? {
        appState.creditChannels.first { $0.code == installmentChannelCode }
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "添置随身器物与在役固资",
            width: ArchiveSheetWidth.compact,
            isSubmitting: isSubmitting,
            isSubmitDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            submitTitle: "添置并纳入大盘",
            onCancel: onDismiss,
            onSubmit: submitAddGear
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                TextField("设备名称", text: $name)
                    .accessibilityLabel("设备名称")
                    .textFieldStyle(.plain)
                    .focused($isNameFocused)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("规格参数", text: $spec)
                    .accessibilityLabel("规格参数")
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                HStack(spacing: ArchiveSpacing.s) {
                    PaperSelect(
                        selection: $category,
                        options: appState.gearCategories.map { PaperSelectOption(value: $0, label: $0) },
                        label: "器物分类："
                    )

                    HStack(spacing: ArchiveSpacing.xs) {
                        Text("¥")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption, weight: .bold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        TextField("购入金额", text: $priceYuan)
                            .accessibilityLabel("购入金额")
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                    }
                    .padding(.horizontal, ArchiveSpacing.s)
                    .frame(height: 32)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                HStack(spacing: ArchiveSpacing.s) {
                    PaperDatePicker(selection: $purchaseDate, enableTime: false, label: "购入日期")
                    Text("（可选过去日期补录旧设备）")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Toggle("伴生记录一笔支出流水", isOn: $createTransaction)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .onChange(of: createTransaction) { _, isOn in
                        if !isOn { isInstallment = false }
                    }

                CreditChannelInstallmentSection(
                    channels: appState.creditChannels,
                    hubURLString: appState.hubURLString,
                    isInstallment: $isInstallment,
                    channelCode: $installmentChannelCode,
                    months: $installmentMonths,
                    amountCents: FormatUtils.parseYuanToCents(priceYuan) ?? 0,
                    toggleTitle: "按分期购入（生成分期账单）",
                    isToggleDisabled: !createTransaction,
                    showEmptyHint: createTransaction
                )

                if createTransaction && !isInstallment {
                    let options = appState.paymentMethods.isEmpty
                        ? ["微信支付", "支付宝", "银行卡", "现金"]
                        : appState.paymentMethods
                    PaperSelect(
                        selection: $paymentMethod,
                        options: options.map { PaperSelectOption(value: $0, label: $0) },
                        label: "扣款账户："
                    )
                }

                TextField("手记", text: $note)
                    .accessibilityLabel("设备手记")
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
            isNameFocused = true
        }
    }

    private func submitAddGear() {
        guard !isSubmitting else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let cents = FormatUtils.parseYuanToCents(priceYuan) ?? 0
        let effectiveInstallment = isInstallment && createTransaction
        let channel = selectedCreditChannel
        if effectiveInstallment {
            guard let channel else {
                errorText = "请先前往 Web 展厅后台「资产 → 渠道管理」配置并选择分期渠道"
                return
            }
            guard channel.repaymentDay >= 1 && channel.repaymentDay <= 31 else {
                errorText = "分期渠道还款日无效（须在 1~31 日之间）"
                return
            }
        }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = AddGearAssetRequest(
                    name: cleanName,
                    spec: spec.isEmpty ? nil : spec,
                    category: category,
                    priceCents: cents,
                    purchaseDate: FormatUtils.beijingDateString(from: purchaseDate),
                    note: note.isEmpty ? nil : note,
                    createTransaction: createTransaction,
                    paymentMethod: paymentMethod,
                    isInstallment: effectiveInstallment,
                    installmentChannelCode: effectiveInstallment ? installmentChannelCode : nil,
                    installmentTotalAmount: effectiveInstallment ? cents : nil,
                    installmentMonths: effectiveInstallment ? installmentMonths : nil,
                    repaymentDay: effectiveInstallment ? channel?.repaymentDay : nil
                )
                _ = try await APIClient.shared.addGearAsset(req)
                await appState.loadConfigAndProfile()
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
