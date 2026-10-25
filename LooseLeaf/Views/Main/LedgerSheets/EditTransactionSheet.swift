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

    // ── 分期编辑（2026-10-22 补齐）────────────────────────────────
    // 原先这个弹窗**完全没有分期 UI**：既不能把一笔账改成分期，
    // 也不能取消分期 —— 用户在桌面端上没有任何补救路径。
    @State private var wantsInstallment: Bool
    /// 用户是否**显式**动过分期开关
    ///
    /// 关键：没动过就不许改分期 —— 否则「支出 → 收入 → 支出」这种来回切换
    /// 会被误判成「用户取消了分期」，一次无心的类型切换就把分期静默抹掉。
    @State private var installmentTouched: Bool = false
    @State private var installmentChannelCode: String
    @State private var installmentMonths: Int

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
        // 分期：原账目是分期就默认勾上（用户不勾 = 明确取消）
        _wantsInstallment = State(initialValue: transaction.isInstallment == true)
        // 渠道无硬编码兜底：空值由视图归一到用户真实渠道列表的首项
        _installmentChannelCode = State(initialValue: transaction.installmentChannelCode ?? "")
        _installmentMonths = State(initialValue: transaction.installmentMonths ?? 12)
    }

    /// 可选信贷渠道（不再伪造内置兜底 —— 渠道为空时禁用分期并提示先登记，
    /// 避免「界面显示占位符、提交却发出幽灵渠道」）
    private var availableCreditChannels: [CreditChannel] {
        appState.creditChannels
    }

    /// 当前选定渠道（还款日**单源**：账单还款日一律由渠道派生，绝不自由编辑）
    private var selectedCreditChannel: CreditChannel? {
        availableCreditChannels.first { $0.code == installmentChannelCode }
    }

    /// 渠道归一：当前选择不在渠道列表里（含空值）时回落到列表首项
    private func normalizeInstallmentChannel() {
        guard let first = availableCreditChannels.first else { return }
        if !availableCreditChannels.contains(where: { $0.code == installmentChannelCode }) {
            installmentChannelCode = first.code
        }
    }

    /// 本次保存会**显式取消**分期
    ///
    /// 两种情形：
    /// 1. 原账目是分期，用户**显式**关掉了开关；
    /// 2. 原账目是分期，而收支类型被改成了**收入**（收入没有分期）。
    ///
    /// 「支出 → 收入 → 支出」来回切换**不会**命中 ——
    /// 判定用的是保存时的最终类型。
    private var willCancelInstallment: Bool {
        guard transaction.isInstallment == true else { return false }
        if type != "expense" { return true }
        return installmentTouched && !wantsInstallment
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
                    // 关键：**不要**在这里清掉分期勾选。
                    // 收入没有分期，但「切换类型」本身不是「取消分期」的意图 ——
                    // 用户「支出 → 收入 → 支出」来回切一次，
                    // 分期就被静默抹掉了（账期、负债全没，用户毫无察觉）。
                    // 真正的取消必须由用户**显式**拨动分期开关。
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

            // ── 分期开关（仅支出可分期；渠道未登记时禁用并提示）──────────────
            if type == "expense" {
                Toggle("分期付款", isOn: $wantsInstallment)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .disabled(availableCreditChannels.isEmpty)
                    .help(availableCreditChannels.isEmpty ? "请先在信贷渠道管理中登记渠道" : "")
                    .onChange(of: wantsInstallment) { _, isOn in
                        // 记录「用户显式动过」—— 类型切换不得等同于取消分期
                        installmentTouched = true
                        // 勾选分期时把渠道归一到列表首项（渠道无硬编码默认值）
                        if isOn {
                            normalizeInstallmentChannel()
                        }
                    }
                    .onChange(of: appState.creditChannels) { _, _ in
                        // 渠道列表就绪/刷新后同样归一
                        if wantsInstallment {
                            normalizeInstallmentChannel()
                        }
                    }

                if availableCreditChannels.isEmpty {
                    Text("信贷分期需要先在「资产大盘 → 渠道管理」中登记渠道与每月还款日。")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }

            if wantsInstallment && type == "expense" {
                // 与「录入设备」弹窗保持同一形态：渠道 + 期数两个下拉，
                // 还款日**不再单独采集** —— 单源化为「所选渠道的还款日」
                //（渠道 label 即展示「每月X日」，切换渠道随之更新），
                // 杜绝「渠道 15 日、账单却记 10 日」的幽灵分叉。
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

                if let cents = FormatUtils.parseYuanToCents(amountYuan), cents > 0, installmentMonths > 0 {
                    Text("每期 ¥\(FormatUtils.formattedYuan(cents: cents / Int64(installmentMonths))) · 总额 ¥\(FormatUtils.formattedYuan(cents: cents))")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }

            // 明确告知「会取消分期」——破坏性操作不能静默发生
            if willCancelInstallment {
                Text("保存后将**取消分期**：账期、期数、月供与渠道会被一并清空，负债相应减少。")
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
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
                    .paperButtonFocusRing()
                Spacer()
                Button("保存修订") {
                    saveChanges()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
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
        // ── 分期三态（与后端契约严格对齐）────────────────────
        // 关键：单发 `is_installment: false` **不足以**表达「取消分期」。
        // 后端的新契约是「不带 clear_installment ⇒ 保持原值」，
        // 所以「取消分期」必须同时带上 false 与 clear_installment=true，
        // 否则用户点了取消、服务端纹丝不动（Android / Web 上踩过的同一个坑）。
        let intent = InstallmentEditing.intent(
            wantsInstallment: wantsInstallment,
            touched: installmentTouched,
            isExpense: type == "expense",
            transaction: transaction
        )
        // 关键：还款日**单源化** —— 一律由所选渠道派生（2026-10-25 修复），
        // 界面已无独立还款日输入。新开分期必须有渠道；untouched 保持原值不受影响。
        if intent == .apply && selectedCreditChannel == nil {
            errorText = "请先在信贷渠道管理中登记并选择分期渠道"
            return
        }
        let installmentFields = InstallmentEditing.fields(
            for: transaction,
            newAmountCents: cents,
            intent: intent,
            channelCode: installmentChannelCode,
            months: installmentMonths,
            // 渠道还款日派生：切渠道 ⇒ 还款日随之更新，不再自由分叉
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
                    // 空串是显式清空；展示层已有「空标题回退到分类」的兜底。
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
                    // 契约 A：用户清空属地城市时显式声明 clear_city，
                    // 服务端据此清空 city_code（优先于 city_code 字段）。
                    // 原先发 nil（省略）被后端按「保持原值」处理，清空静默失效。
                    clearCity: cityCode.isEmpty ? true : nil
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
