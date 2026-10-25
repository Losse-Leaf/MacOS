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
    // 关键（2026-10-25 修复）：渠道无硬编码 "huabei" 默认值 ——
    // 默认跟随用户真实登记的渠道首项（init 中赋值），渠道为空时禁用分期；
    // 还款日不再独立采集，一律由所选渠道派生（还款日单源化）。
    @State private var isInstallment: Bool = false
    @State private var installmentChannelCode: String = ""
    @State private var installmentMonths: Int = 12

    public init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
        // 支付方式默认取用户已配置的首选项，未配置时回落微信支付
        _paymentMethod = State(initialValue: appState.paymentMethods.first ?? "微信支付")
        // 分期渠道默认取用户已登记渠道的首项，未登记时为空（分期开关随之禁用）
        _installmentChannelCode = State(initialValue: appState.creditChannels.first?.code ?? "")
    }

    /// 当前选定渠道（账单还款日的唯一来源）
    private var selectedCreditChannel: CreditChannel? {
        appState.creditChannels.first { $0.code == installmentChannelCode }
    }

    /// 渠道归一：当前选择不在渠道列表里（含空值）时回落到列表首项
    private func normalizeInstallmentChannel() {
        guard let first = appState.creditChannels.first else { return }
        if !appState.creditChannels.contains(where: { $0.code == installmentChannelCode }) {
            installmentChannelCode = first.code
        }
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
                .onChange(of: createTransaction) { _, isOn in
                    // 取消伴生流水时联动清空分期意图：原先 is_installment 残留为 true
                    // 仍随请求发出，后端「create_transaction || is_installment」照样落一笔分期账
                    if !isOn {
                        isInstallment = false
                    }
                }

            // 分期购入：与账目分期共用同一套渠道 / 期数语义；
            // 还款日**不单独采集** —— 单源化为「所选渠道的还款日」（label 已展示每月X日）。
            // 渠道未登记时禁用分期并提示先建渠道，杜绝「界面占位符、提交幽灵渠道」。
            Toggle("按分期购入（生成分期账单）", isOn: $isInstallment)
                .toggleStyle(.paperCheckbox)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .disabled(!createTransaction || appState.creditChannels.isEmpty)
                .help(appState.creditChannels.isEmpty ? "请先在信贷渠道管理中登记渠道" : "")
                .onChange(of: isInstallment) { _, isOn in
                    if isOn {
                        normalizeInstallmentChannel()
                    }
                }
                .onChange(of: appState.creditChannels) { _, channels in
                    if isInstallment {
                        guard let first = channels.first else { return }
                        if !channels.contains(where: { $0.code == installmentChannelCode }) {
                            installmentChannelCode = first.code
                        }
                    }
                }

            if isInstallment && createTransaction {
                if appState.creditChannels.isEmpty {
                    Text("信贷分期需要先在「资产大盘 → 渠道管理」中登记渠道与每月还款日。")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
                HStack(spacing: ArchiveSpacing.s) {
                    PaperSelect(
                        selection: $installmentChannelCode,
                        options: appState.creditChannels.map {
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
        // 关键（S3 修复）：is_installment 必须与「伴生流水」开关求交 ——
        // 原先先勾分期再取消伴生流水，请求仍发 is_installment=true，
        // 后端「create_transaction || is_installment」照样落一笔分期账单。
        let effectiveInstallment = isInstallment && createTransaction
        // 还款日单源化：由所选渠道派生；渠道缺失时禁止分期提交
        let channel = selectedCreditChannel
        if effectiveInstallment {
            guard let channel else {
                errorText = "请先在信贷渠道管理中登记并选择分期渠道"
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
                    name: name,
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
