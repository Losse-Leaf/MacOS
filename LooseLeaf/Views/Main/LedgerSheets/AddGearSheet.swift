import SwiftUI

/// 添置随身设备弹窗 (AddGearSheet)
/// 从 LedgerAssetsView 中拆出的独立 Sheet 组件：
/// 负责登记随身器物与在役固资，并可伴生记录一笔支出流水。
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

// MARK: - 独立弹窗组件：添置随身设备 (AddGearSheet)

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

    // 补档：购入日期可选过去任意一天（默认今天）
    @State private var purchaseDate: Date = Date()
    // 分期购入
    @State private var isInstallment: Bool = false
    @State private var installmentChannelCode: String = "huabei"
    @State private var installmentMonths: Int = 12
    @State private var repaymentDay: Int = 10

    public init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
        // 支付方式默认取用户已配置的首选项，未配置时回落微信支付
        _paymentMethod = State(initialValue: appState.paymentMethods.first ?? "微信支付")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            Text("添置随身器物与在役固资")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("设备名称", text: $name)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("规格参数", text: $spec)
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
                Text("（可选择过去的日期补录旧设备）")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Toggle("伴生记录一笔支出流水", isOn: $createTransaction)
                .toggleStyle(.paperCheckbox)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))

            // 分期购入：与账目分期共用同一套渠道 / 期数 / 还款日语义
            Toggle("按分期购入（生成分期账单）", isOn: $isInstallment)
                .toggleStyle(.paperCheckbox)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .disabled(!createTransaction)

            if isInstallment && createTransaction {
                HStack(spacing: ArchiveSpacing.s) {
                    PaperSelect(
                        selection: $installmentChannelCode,
                        options: (appState.creditChannels.isEmpty
                                   ? [CreditChannel(id: 1, code: "huabei", name: "花呗", repaymentDay: 10, isBuiltin: true)]
                                   : appState.creditChannels
                        ).map { PaperSelectOption(value: $0.code, label: "\($0.name) (每月\($0.repaymentDay)日)") },
                        label: "分期渠道："
                    )

                    PaperSelect(
                        selection: $installmentMonths,
                        options: ArchiveInstallmentOptions.installmentOptions.map {
                            PaperSelectOption(value: $0, label: "\($0) 期")
                        },
                        label: "期数："
                    )

                    PaperSelect(
                        selection: $repaymentDay,
                        options: (1...31).map { PaperSelectOption(value: $0, label: "每月 \($0) 日") },
                        label: "还款日："
                    )
                }
            }

            TextField("手记", text: $note)
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
                    .paperButtonFocusRing()
                Spacer()
                Button("添置并纳入大盘") {
                    submitAddGear()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(
            minWidth: ArchiveSheetWidth.compact,
            idealWidth: ArchiveSheetWidth.compact,
            maxWidth: ArchiveSheetWidth.compact
        )
        .background(ArchivePalette.archivePaper)
    }

    private func submitAddGear() {
        let cents = FormatUtils.parseYuanToCents(priceYuan) ?? 0
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = AddGearAssetRequest(
                    name: name,
                    spec: spec.isEmpty ? nil : spec,
                    category: category,
                    priceCents: cents,
                    purchaseDate: FormatUtils.beijingDateString(from: purchaseDate),
                    note: note.isEmpty ? nil : note,
                    createTransaction: createTransaction,
                    paymentMethod: paymentMethod,
                    isInstallment: isInstallment,
                    installmentChannelCode: isInstallment ? installmentChannelCode : nil,
                    installmentTotalAmount: isInstallment ? cents : nil,
                    installmentMonths: isInstallment ? installmentMonths : nil,
                    repaymentDay: isInstallment ? repaymentDay : nil
                )
                _ = try await APIClient.shared.addGearAsset(req)
                // 器物在服务端会落一条伴生散页（时间流的一级数据），需连带刷新
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
