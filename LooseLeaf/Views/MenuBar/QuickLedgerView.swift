import SwiftUI

/// 菜单栏极速记账界面 (QuickLedgerView)
/// 遵循 docs/macos.md §1 & §3.1 规范：
/// 支持“42.5 午餐咖啡”一句话语义快记（自动转为 4250 分整型）与大数字金额 + 大地色类目胶囊勾选
/// 收支切换时类目网格必须跟随切换（收入类目 ↔ 支出类目），并重置为对应列表首项
@MainActor
public struct QuickLedgerView: View {
    @Bindable var appState: AppState
    var onSubmitted: (() -> Void)?

    @State private var smartInput: String = ""
    @State private var amountString: String = ""
    @State private var titleString: String = ""
    @State private var selectedType: String = "expense"
    @State private var selectedCategory: String = "餐饮"
    @State private var selectedPayment: String = "微信支付"
    @State private var selectedCityCode: String = ""
    @State private var selectedCityName: String = ""
    @State private var occurredAt: Date = Date()
    @State private var showDatePicker: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var localError: String?
    /// 提交成功后的面板内确认（菜单栏窗口看不到全局横幅，此处给出就地回执）
    @State private var localSuccess: String?

    @FocusState private var isSmartFieldFocused: Bool

    public init(appState: AppState, onSubmitted: (() -> Void)? = nil) {
        self.appState = appState
        self.onSubmitted = onSubmitted
    }

    /// 当前收支形态下的可用类目
    /// 收入形态必须使用 `incomeCategories`（工资收入 / 二手回血…），支出形态使用 `expenseCategories`
    private var activeCategories: [String] {
        selectedType == "income" ? appState.incomeCategories : appState.expenseCategories
    }

    /// 当前形态下的类目标题
    private var categorySectionTitle: String {
        selectedType == "income" ? "收入类目" : "支出类目"
    }

    /// 极速指令是否显式携带正负号（显式符号的优先级高于用户手动选择的收支形态）
    private var smartInputHasExplicitSign: Bool {
        let trimmed = smartInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("+") || trimmed.hasPrefix("-")
    }

    private var resolvedQuickParsed: FormatUtils.QuickLedgerParsed? {
        if !smartInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 未显式带符号时把当前收支形态注入语义解析：
            // 收入形态补 “+” 前缀，使类目推断也按收入口径工作（「+」由标签页形态决定，非用户手输）
            let source: String
            if selectedType == "income" && !smartInputHasExplicitSign {
                source = "+" + smartInput.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                source = smartInput
            }
            return FormatUtils.parseQuickLedgerInput(
                source,
                defaultCategory: selectedCategory,
                knownCategories: activeCategories
            )
        }
        guard let cents = FormatUtils.parseYuanToCents(amountString), cents > 0 else {
            return nil
        }
        let cleanTitle = titleString.trimmingCharacters(in: .whitespacesAndNewlines)
        return FormatUtils.QuickLedgerParsed(
            amountCents: cents,
            type: selectedType,
            category: selectedCategory,
            title: cleanTitle.isEmpty ? selectedCategory : cleanTitle
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            // 1. 一句话极速语义记账框（主输入常驻可见，不随滚动移出视野）
            smartInputSection

            // 2. 可滚动录入区（分项金额 / 类目胶囊网格 / 补记时刻）
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                    typeAmountSection
                    categorySection
                    if showDatePicker {
                        HStack(spacing: ArchiveSpacing.s) {
                            PaperDateTimePicker(selection: $occurredAt, label: "入账时间", showQuickShortcuts: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, ArchiveSpacing.xxs)
                        .padding(.vertical, ArchiveSpacing.xxs)
                    }
                    monthlySpectrumSection
                }
                .padding(.bottom, ArchiveSpacing.xs)
            }
            .frame(minHeight: 150)

            // 3. 固定提交条（支付方式 / 补记 / 属地 / 入账）
            submitBar

            // 4. 就地反馈（错误与成功确认，紧贴提交按钮）
            feedbackBar
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            isSmartFieldFocused = true
            if let firstPay = appState.paymentMethods.first {
                selectedPayment = firstPay
            }
            normalizeSelectedCategory()
        }
        .onChange(of: selectedType) { _, _ in
            normalizeSelectedCategory()
        }
        .onChange(of: smartInput) { _, _ in
            syncTypeWithSmartInput()
        }
    }

    // MARK: - 一句话极速语义记账框

    private var smartInputSection: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
            HStack {
                Text("极速指令输入")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer(minLength: 0)
                if let parsed = resolvedQuickParsed {
                    Text("\(parsed.type == "income" ? "+" : "-")\(FormatUtils.formattedYuan(cents: parsed.amountCents, includeSymbol: true)) · \(parsed.category)")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .lineLimit(1)
                }
            }

            TextField("记一笔账，如：42.5 咖啡…", text: $smartInput)
                .accessibilityLabel("快速记账输入")
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .focused($isSmartFieldFocused)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                )
                .accessibilityLabel("极速指令输入")
                .onSubmit {
                    submitLedger()
                }
        }
    }

    // MARK: - 收支切换与分项金额

    private var typeAmountSection: some View {
        HStack(spacing: ArchiveSpacing.s) {
            HStack(spacing: ArchiveSpacing.xs) {
                PaperPillButton(title: "支出", isSelected: selectedType == "expense") {
                    selectType("expense")
                }
                PaperPillButton(title: "收入", isSelected: selectedType == "income") {
                    selectType("income")
                }
            }

            HStack(spacing: ArchiveSpacing.xs) {
                Text("¥")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("0.00", text: $amountString)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .frame(width: 72)
                    .accessibilityLabel("金额")
            }
            .padding(.horizontal, ArchiveSpacing.s)
            .padding(.vertical, ArchiveSpacing.xs)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )

            TextField("摘要说明", text: $titleString)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .padding(.horizontal, ArchiveSpacing.s)
                .padding(.vertical, ArchiveSpacing.xs)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
                .accessibilityLabel("摘要说明")
        }
    }

    // MARK: - 常用类目胶囊网格

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
            Text(categorySectionTitle)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(ArchivePalette.inkMuted)

            // 数据源随收支类型切换：收入形态遍历 incomeCategories，支出形态遍历 expenseCategories
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: ArchiveSpacing.xs)], alignment: .leading, spacing: ArchiveSpacing.xs) {
                ForEach(activeCategories, id: \.self) { category in
                    PaperPillButton(
                        title: category,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
        }
    }

    // MARK: - 本月收支微光谱概览

    private var monthlySpectrumSection: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
            Divider()
                .overlay(ArchivePalette.borderSubtle)
            HStack {
                Text("\(appState.transactionSummary.month) 月累计支出")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer(minLength: 0)
                Text(FormatUtils.formattedYuan(cents: appState.transactionSummary.totalExpense, includeSymbol: true))
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
            }
            ExpenseSpectrumBar(summary: appState.transactionSummary, showLegend: false)
        }
    }

    // MARK: - 支付方式与提交栏

    private var submitBar: some View {
        HStack(spacing: ArchiveSpacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ArchiveSpacing.xs) {
                    ForEach(appState.paymentMethods, id: \.self) { method in
                        Button {
                            selectedPayment = method
                        } label: {
                            Text(method)
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(selectedPayment == method ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                                .padding(.horizontal, ArchiveSpacing.xs)
                                .padding(.vertical, ArchiveSpacing.xxs)
                                .background(
                                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                        .stroke(selectedPayment == method ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("支付方式 \(method)")
                        .accessibilityValue(selectedPayment == method ? "已选中" : "未选中")
                    }
                }
            }

            Spacer(minLength: 0)

            // 补记历史时刻（命中区不小于 28pt）
            Button {
                showDatePicker.toggle()
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(showDatePicker ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                    .padding(ArchiveSpacing.xs)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("补记历史时刻")
            .help("补记过去发生的账目时刻")

            PaperCityPicker(
                selectedCode: $selectedCityCode,
                selectedName: $selectedCityName,
                placeholder: appState.profile.displayCity.isEmpty ? "属地" : appState.profile.displayCity
            )

            Button {
                submitLedger()
            } label: {
                HStack(spacing: ArchiveSpacing.xs) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: ArchiveTypography.Scale.caption))
                    Text(isSubmitting ? "入账中…" : "记入账本 ⌘↩")
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(resolvedQuickParsed == nil || isSubmitting)
            .accessibilityLabel("记入账本")
        }
    }

    // MARK: - 就地反馈（错误与成功确认）

    @ViewBuilder
    private var feedbackBar: some View {
        if let localError {
            feedbackStrip(icon: "exclamationmark.triangle.fill", text: localError, tint: ArchivePalette.accentWarm)
        } else if let localSuccess {
            feedbackStrip(icon: "checkmark.circle.fill", text: localSuccess, tint: ArchivePalette.accentMoss)
        }
    }

    /// 统一反馈条样式（错误暖色 / 成功苔绿）
    private func feedbackStrip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: ArchiveSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(tint)
            Text(text)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ArchiveSpacing.s)
        .padding(.vertical, ArchiveSpacing.xs)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 收支形态与类目联动

    /// 切换收支类型：类目网格与当前类目必须同步切换（收入 ↔ 支出）
    /// 并把当前类目重置为新类型列表的首项，避免出现「收入 + 餐饮」的越界组合
    private func selectType(_ type: String) {
        // 重复点击当前形态时不做任何事，避免误重置用户已选的类目
        guard type != selectedType else { return }
        selectedType = type
        selectedCategory = (type == "income" ? appState.incomeCategories : appState.expenseCategories).first ?? selectedCategory
    }

    /// 校正当前类目是否仍存在于当前形态的类目字典中（字典刷新后自动回落）
    private func normalizeSelectedCategory() {
        let categories = activeCategories
        guard !categories.contains(selectedCategory) else { return }
        selectedCategory = categories.first ?? selectedCategory
    }

    /// 极速指令自带正负号时（如 “+5000 工资收入”）自动切到对应收支形态与类目字典
    /// 未带符号时不干预用户手动选择的收支形态
    private func syncTypeWithSmartInput() {
        guard smartInputHasExplicitSign else { return }
        guard let parsed = FormatUtils.parseQuickLedgerInput(
            smartInput,
            defaultCategory: selectedCategory,
            // 类型尚未切换时，用两套字典一起识别，否则“工资收入”会被当成标题。
            knownCategories: appState.expenseCategories + appState.incomeCategories
        ) else { return }
        guard parsed.type != selectedType else { return }
        selectType(parsed.type)
    }

    // MARK: - 提交

    private func submitLedger() {
        guard let parsed = resolvedQuickParsed, !isSubmitting else { return }
        isSubmitting = true
        localError = nil
        localSuccess = nil

        var cityCodeToSubmit: String? = selectedCityCode.isEmpty ? nil : selectedCityCode
        if cityCodeToSubmit == nil && !smartInput.isEmpty {
            cityCodeToSubmit = CityDictionary.code(forLocation: smartInput)
        }

        Task { @MainActor in
            do {
                let queuedOffline = try await appState.submitQuickLedger(
                    amountCents: parsed.amountCents,
                    type: parsed.type,
                    category: parsed.category,
                    title: parsed.title,
                    paymentMethod: selectedPayment,
                    cityCode: cityCodeToSubmit,
                    occurredAt: FormatUtils.beijingISOString(from: occurredAt)
                )
                smartInput = ""
                amountString = ""
                titleString = ""
                selectedCityCode = ""
                selectedCityName = ""
                occurredAt = Date()
                showDatePicker = false
                isSubmitting = false
                presentSuccess(
                    queuedOffline
                        ? "账单已暂存至本地发件箱，网络恢复后自动同步"
                        : "已记入账本：\(FormatUtils.formattedYuan(cents: parsed.amountCents, includeSymbol: true))"
                )
            } catch {
                localError = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    /// 提交成功回执：面板内展示片刻后再收起（菜单栏窗口看不到全局横幅）
    private func presentSuccess(_ message: String) {
        localSuccess = message
        localError = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard localSuccess == message else { return }
            localSuccess = nil
            onSubmitted?()
        }
    }
}

// MARK: - 预览 (Preview)

/// 预览用 mock 数据（复用 AppState 单例，仅注入面板所需的展示数据）
@MainActor
private enum QuickLedgerPreviewData {
    static var sample: AppState {
        let state = AppState.shared
        state.expenseCategories = ["餐饮", "交通", "购物", "数码器材", "娱乐", "住房"]
        state.incomeCategories = ["工资收入", "二手回血", "稿酬设计", "投资理财"]
        state.paymentMethods = ["微信支付", "支付宝", "银行卡", "现金"]
        return state
    }
}

#Preview("快速记账面板") {
    QuickLedgerView(appState: QuickLedgerPreviewData.sample)
        .frame(width: 380, height: 460)
}
