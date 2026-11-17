import SwiftUI

/// 菜单栏极速记账界面 (QuickLedgerView)
/// 遵循 docs/macos.md §1 & §3.1 规范：
/// 支持“42.5 午餐咖啡”一句话语义快记（自动转为 4250 分整型）与大数字金额 + 大地色类目胶囊勾选；
/// 草稿字段全部托管在 `appState.quickDraft`，切换「极速记录 / 快速记账」或在菜单栏与 ⌘⇧L 面板间切换永不丢输入。
@MainActor
public struct QuickLedgerView: View {
    @Bindable var appState: AppState
    var onSubmitted: (() -> Void)?

    @State private var isSubmitting: Bool = false
    @State private var localError: String?
    @State private var localSuccess: String?

    @FocusState private var isSmartFieldFocused: Bool

    public init(appState: AppState, onSubmitted: (() -> Void)? = nil) {
        self.appState = appState
        self.onSubmitted = onSubmitted
    }

    private var draft: QuickCaptureDraft {
        appState.quickDraft
    }

    private var activeCategories: [String] {
        draft.ledgerSelectedType == "income" ? appState.incomeCategories : appState.expenseCategories
    }

    private var categorySectionTitle: String {
        draft.ledgerSelectedType == "income" ? "收入类目" : "支出类目"
    }

    private var smartInputHasExplicitSign: Bool {
        let trimmed = draft.ledgerSmartInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("+") || trimmed.hasPrefix("-")
    }

    private var effectiveSelectedCategory: String {
        if activeCategories.contains(draft.ledgerSelectedCategory) {
            return draft.ledgerSelectedCategory
        }
        return activeCategories.first ?? "餐饮"
    }

    private var effectiveSelectedPayment: String {
        if appState.paymentMethods.contains(draft.ledgerSelectedPayment) {
            return draft.ledgerSelectedPayment
        }
        return appState.paymentMethods.first ?? "微信支付"
    }

    private var resolvedQuickParsed: FormatUtils.QuickLedgerParsed? {
        if !draft.ledgerSmartInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let source: String
            if draft.ledgerSelectedType == "income" && !smartInputHasExplicitSign {
                source = "+" + draft.ledgerSmartInput.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                source = draft.ledgerSmartInput
            }
            return FormatUtils.parseQuickLedgerInput(
                source,
                defaultCategory: effectiveSelectedCategory,
                knownCategories: activeCategories
            )
        }
        guard let cents = FormatUtils.parseYuanToCents(draft.ledgerAmountString), cents > 0 else {
            return nil
        }
        let cleanTitle = draft.ledgerTitleString.trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = effectiveSelectedCategory
        return FormatUtils.QuickLedgerParsed(
            amountCents: cents,
            type: draft.ledgerSelectedType,
            category: cat,
            title: cleanTitle.isEmpty ? cat : cleanTitle
        )
    }

    public var body: some View {
        @Bindable var draft = appState.quickDraft
        return VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            smartInputSection

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                    typeAmountSection
                    categorySection
                    if draft.ledgerShowDatePicker {
                        HStack(spacing: ArchiveSpacing.s) {
                            PaperDateTimePicker(selection: $draft.ledgerOccurredAt, label: "入账时间", showQuickShortcuts: true)
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

            submitBar
            feedbackBar
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            isSmartFieldFocused = true
            if draft.ledgerSelectedPayment.isEmpty, let firstPay = appState.paymentMethods.first {
                draft.ledgerSelectedPayment = firstPay
            }
            normalizeSelectedCategory()
        }
        .onChange(of: draft.ledgerSelectedType) { _, _ in
            normalizeSelectedCategory()
        }
        .onChange(of: draft.ledgerSmartInput) { _, _ in
            syncTypeWithSmartInput()
        }
    }

    // MARK: - 一句话极速语义记账框

    private var smartInputSection: some View {
        @Bindable var draft = appState.quickDraft
        return VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
            HStack {
                Text("极速指令输入")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer(minLength: 0)
                Text(resolvedQuickParsed.map { "\($0.type == "income" ? "+" : "-")\(FormatUtils.formattedYuan(cents: $0.amountCents, includeSymbol: true)) · \($0.category)" } ?? "自动识别金额与类目")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption, weight: .semibold))
                    .foregroundStyle(resolvedQuickParsed != nil ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                    .lineLimit(1)
            }

            TextField("记一笔账，如：42.5 咖啡…", text: $draft.ledgerSmartInput)
                .accessibilityLabel("快速记账自然语义输入")
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
                .onSubmit {
                    submitLedger()
                }
        }
    }

    // MARK: - 收支切换与分项金额

    private var typeAmountSection: some View {
        @Bindable var draft = appState.quickDraft
        return HStack(spacing: ArchiveSpacing.s) {
            HStack(spacing: ArchiveSpacing.xs) {
                PaperPillButton(title: "支出", isSelected: draft.ledgerSelectedType == "expense") {
                    selectType("expense")
                }
                PaperPillButton(title: "收入", isSelected: draft.ledgerSelectedType == "income") {
                    selectType("income")
                }
            }

            HStack(spacing: ArchiveSpacing.xs) {
                Text("¥")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("0.00", text: $draft.ledgerAmountString)
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

            TextField("摘要说明", text: $draft.ledgerTitleString)
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
        let currentCat = effectiveSelectedCategory
        return VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
            Text(categorySectionTitle)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(ArchivePalette.inkMuted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: ArchiveSpacing.xs)], alignment: .leading, spacing: ArchiveSpacing.xs) {
                ForEach(activeCategories, id: \.self) { category in
                    PaperPillButton(
                        title: category,
                        isSelected: currentCat == category
                    ) {
                        appState.quickDraft.ledgerSelectedCategory = category
                    }
                }
            }
            .frame(minHeight: 62, alignment: .top)
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
        @Bindable var draft = appState.quickDraft
        let currentPay = effectiveSelectedPayment
        return HStack(spacing: ArchiveSpacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ArchiveSpacing.xs) {
                    ForEach(appState.paymentMethods, id: \.self) { method in
                        let isSelected = (currentPay == method)
                        Button {
                            draft.ledgerSelectedPayment = method
                        } label: {
                            Text(method)
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(isSelected ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                                .padding(.horizontal, ArchiveSpacing.xs)
                                .padding(.vertical, 4)
                                .frame(minHeight: ArchiveHitTarget.minPointer)
                                .background(
                                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                        .stroke(isSelected ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: 0.5)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                        .accessibilityLabel("支付方式 \(method)")
                        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                draft.ledgerShowDatePicker.toggle()
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(draft.ledgerShowDatePicker ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                    .padding(ArchiveSpacing.xs)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
            .accessibilityLabel("补记历史时刻")
            .help("补记过去发生的账目时刻")

            PaperCityPicker(
                selectedCode: $draft.ledgerSelectedCityCode,
                selectedName: $draft.ledgerSelectedCityName,
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

    // MARK: - 就地反馈

    @ViewBuilder
    private var feedbackBar: some View {
        if let localError {
            QuickFeedbackStrip(icon: "exclamationmark.triangle.fill", text: localError, tint: ArchivePalette.accentWarm)
        } else if let localSuccess {
            QuickFeedbackStrip(icon: "checkmark.circle.fill", text: localSuccess, tint: ArchivePalette.accentMoss)
        }
    }

    // MARK: - 收支形态与类目联动

    private func selectType(_ type: String) {
        guard type != draft.ledgerSelectedType else { return }
        draft.ledgerSelectedType = type
        draft.ledgerSelectedCategory = (type == "income" ? appState.incomeCategories : appState.expenseCategories).first ?? draft.ledgerSelectedCategory
    }

    private func normalizeSelectedCategory() {
        let categories = activeCategories
        guard !categories.contains(draft.ledgerSelectedCategory) else { return }
        draft.ledgerSelectedCategory = categories.first ?? draft.ledgerSelectedCategory
    }

    private func syncTypeWithSmartInput() {
        guard smartInputHasExplicitSign else { return }
        guard let parsed = FormatUtils.parseQuickLedgerInput(
            draft.ledgerSmartInput,
            defaultCategory: effectiveSelectedCategory,
            knownCategories: appState.expenseCategories + appState.incomeCategories
        ) else { return }
        guard parsed.type != draft.ledgerSelectedType else { return }
        selectType(parsed.type)
    }

    // MARK: - 提交

    private func submitLedger() {
        guard let parsed = resolvedQuickParsed, !isSubmitting else { return }
        isSubmitting = true
        localError = nil
        localSuccess = nil

        let cityCodeToSubmit: String? = draft.ledgerSelectedCityCode.isEmpty ? nil : draft.ledgerSelectedCityCode
        let payToSubmit = effectiveSelectedPayment
        let dateToSubmit = draft.ledgerOccurredAt

        Task { @MainActor in
            do {
                let queuedOffline = try await appState.submitQuickLedger(
                    amountCents: parsed.amountCents,
                    type: parsed.type,
                    category: parsed.category,
                    title: parsed.title,
                    paymentMethod: payToSubmit,
                    cityCode: cityCodeToSubmit,
                    occurredAt: FormatUtils.beijingISOString(from: dateToSubmit)
                )
                draft.resetLedger()
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

    private func presentSuccess(_ message: String) {
        localSuccess = message
        localError = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard localSuccess == message else { return }
            localSuccess = nil
            onSubmitted?()
        }
    }
}

// MARK: - 预览 (Preview)

#if DEBUG
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
#endif
