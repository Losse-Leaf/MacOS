import SwiftUI
import AppKit

/// 独立抽离的双模记账控制台（隔离输入态，杜绝每次敲击字符触发父级数千条账目重筛与重排）
@MainActor
private struct LedgerComposerCard: View {
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
    @State private var formCityCode: String = ""
    @State private var formCityName: String = ""
    @State private var formOccurredAt: Date = Date()
    @State private var formLinkGear: Bool = false
    @State private var formGearCategory: String = "数码器材"
    @State private var formGearSpec: String = ""
    @State private var formIsInstallment: Bool = false
    @State private var formInstallmentChannelCode: String = ""
    @State private var formInstallmentMonths: Int = 12
    @State private var formRepaymentDay: Int = 10
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
            self._formRepaymentDay = State(initialValue: firstCh.repaymentDay)
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

                        Toggle("建入固资大盘", isOn: $formLinkGear)
                            .toggleStyle(.paperCheckbox)
                            .font(ArchiveTypography.bodySans(size: 11.5))

                        if formType == "expense" {
                            Toggle("分期付款", isOn: $formIsInstallment)
                                .toggleStyle(.paperCheckbox)
                                .font(ArchiveTypography.bodySans(size: 11.5))
                                .onChange(of: formIsInstallment) { _, isOn in
                                    if isOn, formInstallmentChannelCode.isEmpty, let first = availableCreditChannels.first {
                                        formInstallmentChannelCode = first.code
                                        formRepaymentDay = first.repaymentDay
                                    }
                                }
                        }
                    }

                    HStack(spacing: 10) {
                        Text("时空：")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)

                        PaperDatePicker(selection: $formOccurredAt)
                        PaperTimePicker(selection: $formOccurredAt)

                        Spacer()

                        HStack(spacing: ArchiveSpacing.xs) {
                            Text("省市：")
                                .font(ArchiveTypography.bodySans(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkMuted)

                            PaperCityPicker(
                                selectedCode: $formCityCode,
                                selectedName: $formCityName,
                                placeholder: appState.profile.displayCity.isEmpty ? "选择省市" : appState.profile.displayCity
                            )
                        }
                    }

                    if formLinkGear {
                        HStack(spacing: ArchiveSpacing.s) {
                            PaperSelect(
                                selection: $formGearCategory,
                                options: appState.gearCategories.map { PaperSelectOption(value: $0, label: $0) },
                                label: "固资分类："
                            )

                            TextField("规格参数", text: $formGearSpec)
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                                .padding(6)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                        }
                    }

                    if formIsInstallment && formType == "expense" {
                        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                            if availableCreditChannels.isEmpty {
                                Text("尚未从中枢加载到可用信贷分期渠道，请联网同步后再试。")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            } else {
                                HStack(spacing: ArchiveSpacing.s) {
                                    Text("信贷渠道：")
                                        .font(ArchiveTypography.bodySans(size: 11.5))
                                        .foregroundStyle(ArchivePalette.inkMuted)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(availableCreditChannels) { ch in
                                                PaperPillButton(
                                                    title: "\(ch.name) (每月\(ch.repaymentDay)日)",
                                                    isSelected: formInstallmentChannelCode == ch.code
                                                ) {
                                                    formInstallmentChannelCode = ch.code
                                                    formRepaymentDay = ch.repaymentDay
                                                }
                                            }
                                        }
                                    }
                                    .horizontalFadeMask()

                                    Spacer()
                                }
                            }

                            HStack(spacing: ArchiveSpacing.m) {
                                HStack(spacing: 6) {
                                    Text("分期期数：")
                                        .font(ArchiveTypography.bodySans(size: 11.5))
                                        .foregroundStyle(ArchivePalette.inkMuted)

                                    ForEach(ArchiveInstallmentOptions.installmentOptions, id: \.self) { months in
                                        PaperPillButton(title: "\(months) 期", isSelected: formInstallmentMonths == months) {
                                            formInstallmentMonths = months
                                        }
                                    }
                                }

                                Divider()
                                    .frame(height: 16)
                                    .overlay(ArchivePalette.borderSubtle)

                                if let ch = availableCreditChannels.first(where: { $0.code == formInstallmentChannelCode }) {
                                    Text("还款日跟随渠道：每月 \(ch.repaymentDay) 日")
                                        .font(ArchiveTypography.monoScale(size: 11.5))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }

                                Spacer()

                                let totalCents = FormatUtils.parseYuanToCents(formAmountYuan) ?? 0
                                let monthlyCents = totalCents > 0 ? totalCents / Int64(max(1, formInstallmentMonths)) : 0
                                Text(totalCents > 0 ? "前 \(max(1, formInstallmentMonths - 1)) 期每期 \(FormatUtils.formattedYuan(cents: monthlyCents, includeSymbol: true))" : "输入金额后自动核算每期")
                                    .font(ArchiveTypography.monoScale(size: 11.5, weight: .semibold))
                                    .foregroundStyle(totalCents > 0 ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                                    .lineLimit(1)
                            }
                        }
                        .padding(10)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                        )
                    }

                    HStack {
                        TextField("备注", text: $formNote)
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
                    cityCode: formCityCode.isEmpty ? nil : formCityCode,
                    occurredAt: FormatUtils.beijingISOString(from: formOccurredAt),
                    isInstallment: isInst,
                    installmentChannelCode: resolvedChannel?.code,
                    installmentTotalAmount: isInst ? cents : nil,
                    installmentMonths: isInst ? months : nil,
                    installmentMonthlyPay: monthlyPay,
                    installmentRemainMonths: isInst ? months : nil,
                    repaymentDay: resolvedChannel?.repaymentDay,
                    linkGearAsset: formLinkGear,
                    gearCategory: formLinkGear ? formGearCategory : nil,
                    gearSpec: formLinkGear ? formGearSpec : nil
                )
                _ = try await SyncManager.shared.submitTransaction(req)
                formAmountYuan = ""
                formTitle = ""
                formNote = ""
                formCityCode = ""
                formCityName = ""
                formOccurredAt = Date()
                formLinkGear = false
                formIsInstallment = false
                await appState.loadTransactionsAndAssets(forceFull: false)
                await appState.loadConfigAndProfile()
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }
}

/// 桌面端独立记账与资产管理中枢视图 (LedgerAssetsView)
/// 严格遵循 docs/backend.md §5.3 & §5.3.1 (RC-53 隐私隔离与 Cents 整型精度)
@MainActor
public struct LedgerAssetsView: View {
    @Bindable var appState: AppState

    @State private var showVisualForm: Bool = false

    public enum LedgerSubTab: String, CaseIterable, Identifiable {
        case ledger = "收支流水"
        case gear = "随身固资与信贷"

        public var id: String { rawValue }
    }

    @State private var activeSubTab: LedgerSubTab = .ledger

    // 筛选与弹窗
    @State private var selectedYear: Int = FormatUtils.beijingCurrentYearMonth().year
    @State private var selectedMonth: Int = FormatUtils.beijingCurrentYearMonth().month
    @State private var customMonthSummary: TransactionSummary?
    @State private var isLoadingSummary: Bool = false
    @State private var filterBySelectedMonth: Bool = true
    @State private var selectedCategoryFilter: String = "全部"
    @State private var visibleTxLimit: Int = 150
    @State private var showCalibrateBalanceSheet: Bool = false
    @State private var isCalibratingBalance: Bool = false
    @State private var showAddGearSheet: Bool = false
    @State private var editingTransaction: Transaction?
    @State private var sellingGear: GearItem?
    @State private var initialBalanceYuanInput: String = ""
    @State private var errorNotice: String?
    @State private var summaryLoadTask: Task<Void, Never>?
    @FocusState private var isCalibrateFieldFocused: Bool

    public init(appState: AppState) {
        self.appState = appState
    }

    private var isCurrentMonthSelected: Bool {
        isCurrentMonth(year: selectedYear, month: selectedMonth)
    }

    private func isCurrentMonth(year: Int, month: Int) -> Bool {
        let now = FormatUtils.beijingCurrentYearMonth()
        return year == now.year && month == now.month
    }

    private var activeSummary: TransactionSummary {
        if isCurrentMonthSelected {
            return appState.transactionSummary
        }
        return customMonthSummary ?? TransactionSummary(
            year: selectedYear,
            month: selectedMonth,
            totalExpense: 0,
            totalIncome: 0,
            balance: 0,
            categoryBreakdown: [:]
        )
    }

    private func changeMonth(by delta: Int) {
        var y = selectedYear
        var m = selectedMonth + delta
        if m < 1 {
            m = 12
            y -= 1
        } else if m > 12 {
            m = 1
            y += 1
        }
        selectedYear = y
        selectedMonth = m
        visibleTxLimit = 150
        reloadSummary(year: y, month: m)
    }

    private func reloadSummary(year: Int, month: Int) {
        summaryLoadTask?.cancel()
        summaryLoadTask = Task { @MainActor in
            await loadSummaryForSelectedMonth(year: year, month: month)
        }
    }

    private func loadSummaryForSelectedMonth(year: Int, month: Int) async {
        if isCurrentMonth(year: year, month: month) {
            customMonthSummary = nil
            return
        }
        isLoadingSummary = true
        defer { isLoadingSummary = false }
        do {
            let fetched = try await APIClient.shared.fetchTransactionSummary(year: year, month: month)
            try Task.checkCancellation()
            guard selectedYear == year, selectedMonth == month else { return }
            customMonthSummary = fetched
        } catch is CancellationError {
            // 已被新的月份切换取代
        } catch {
            guard selectedYear == year, selectedMonth == month else { return }
            errorNotice = "月度汇总加载失败：\(error.localizedDescription)"
        }
    }

    /// 交易流水筛选结果（严格按北京时间 `parsedDate.dateKey` 自然月过滤，修复 UTC 跨月偏移）
    private var filteredTransactions: [Transaction] {
        var list = appState.transactions
        if filterBySelectedMonth {
            let prefix = String(format: "%04d-%02d", selectedYear, selectedMonth)
            list = list.filter { $0.parsedDate.dateKey.hasPrefix(prefix) }
        }
        if selectedCategoryFilter != "全部" {
            list = list.filter { $0.category == selectedCategoryFilter }
        }
        return list
    }

    private var allTransactionCategories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for category in appState.expenseCategories + appState.incomeCategories where seen.insert(category).inserted {
            result.append(category)
        }
        return result
    }

    public var body: some View {
        let transactions = filteredTransactions
        let categories = allTransactionCategories
        let gearList = appState.profile.edcGear

        ScrollView {
            LazyVStack(alignment: .leading, spacing: ArchiveSpacing.l) {
                headerSection

                if let overview = appState.assetsOverview {
                    assetsOverviewGrid(overview)
                }

                if activeSubTab == .ledger {
                    monthlySpectrumCard

                    LedgerComposerCard(
                        appState: appState,
                        showVisualForm: $showVisualForm,
                        errorNotice: $errorNotice
                    )

                    transactionsHeaderSection(categories: categories, transactionCount: transactions.count)

                    if transactions.isEmpty {
                        transactionsEmptyState
                    } else {
                        transactionsList(transactions)
                    }
                } else {
                    if let liabilities = appState.assetsOverview?.channelLiabilities, !liabilities.isEmpty {
                        channelLiabilitiesSection(liabilities)
                    }

                    gearAssetsHeaderSection(gearCount: gearList.count)

                    if gearList.isEmpty {
                        gearEmptyState
                    } else {
                        gearGrid(gearList)
                    }
                }
            }
            .padding(ArchiveSpacing.xl)
        }
        .sheet(isPresented: $showCalibrateBalanceSheet) {
            calibrateLiquidBalanceSheet
        }
        .sheet(isPresented: $showAddGearSheet) {
            addGearSheetView
        }
        .sheet(item: $editingTransaction) { tx in
            editTransactionSheetView(tx)
        }
        .sheet(item: $sellingGear) { gear in
            sellGearSheetView(gear)
        }
        .overlay(alignment: .top) {
            if let errorNotice {
                errorBanner(text: errorNotice)
            }
        }
    }

    private func errorBanner(text: String) -> some View {
        HStack(spacing: ArchiveSpacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.accentWarm)
                .accessibilityHidden(true)

            Text(text)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            PaperIconButton(
                systemName: ArchiveIcon.close.systemName,
                label: "关闭错误提示",
                help: "关闭错误提示",
                size: ArchiveTypography.Scale.micro,
                tint: ArchivePalette.inkMuted
            ) {
                errorNotice = nil
            }
        }
        .padding(.horizontal, ArchiveSpacing.m)
        .padding(.vertical, ArchiveSpacing.s)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.accentWarm.opacity(0.45), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        .padding(.horizontal, ArchiveSpacing.l)
        .padding(.top, ArchiveSpacing.s)
    }

    // MARK: - 1. 页眉

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: ArchiveSpacing.m) {
                    Text("资产大盘与记账")
                        .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    HStack(spacing: 4) {
                        ForEach(LedgerSubTab.allCases) { tab in
                            PaperPillButton(
                                title: tab.rawValue,
                                isSelected: activeSubTab == tab
                            ) {
                                activeSubTab = tab
                            }
                        }
                    }
                }
                Text("个人净资产与日常流水总览 · 每一笔收支皆有归处")
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }
            Spacer()

            HStack(spacing: ArchiveSpacing.s) {
                if activeSubTab == .gear {
                    Button {
                        showAddGearSheet = true
                    } label: {
                        HStack(spacing: ArchiveSpacing.xs) {
                            Image(systemName: "plus.circle")
                            Text("添置随身设备")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    .paperButtonFocusRing()
                }

                Button {
                    if let currentInit = appState.assetsOverview?.initialLiquidBalance {
                        initialBalanceYuanInput = FormatUtils.formattedYuan(cents: currentInit)
                    }
                    errorNotice = nil
                    showCalibrateBalanceSheet = true
                } label: {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Image(systemName: "slider.horizontal.3")
                        Text("校准底数")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
            }
        }
    }

    // MARK: - 2. 资产大盘四维指标卡片

    private func assetsOverviewGrid(_ overview: AssetsOverview) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: ArchiveSpacing.m)], spacing: ArchiveSpacing.m) {
            metricCard(
                title: "总净资产",
                cents: overview.netWorth,
                subtitle: "流动余额 + 在用固资 - 待还分期",
                accent: ArchivePalette.inkPrimary
            )
            metricCard(
                title: "流动可用余额",
                cents: overview.liquidBalance,
                subtitle: "含初始底数 \(FormatUtils.formattedYuan(cents: overview.initialLiquidBalance, includeSymbol: true))",
                accent: ArchivePalette.accentMoss
            )
            metricCard(
                title: "在用器物固资",
                cents: overview.fixedAssets,
                subtitle: "随身设备 \(overview.gearSummary?.activeCount ?? appState.profile.edcGear.filter { $0.status != "sold" }.count) 件在役",
                accent: ArchivePalette.inkSecondary
            )
            metricCard(
                title: "待还信贷总额",
                cents: overview.totalLiabilities,
                subtitle: "月供 \(FormatUtils.formattedYuan(cents: overview.monthlyLiabilities, includeSymbol: true))",
                accent: ArchivePalette.accentWarm
            )
        }
    }

    private func metricCard(title: String, cents: Int64, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ArchiveTypography.bodySans(size: 11.5))
                .foregroundStyle(ArchivePalette.inkMuted)
            Text(FormatUtils.formattedYuan(cents: cents, includeSymbol: true))
                .font(ArchiveTypography.monoScale(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                .foregroundStyle(ArchivePalette.inkMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ArchiveCardMetrics.padding)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 3. 月度收支光谱卡片

    private var monthlySpectrumCard: some View {
        let sum = activeSummary
        return VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            HStack(alignment: .center) {
                HStack(spacing: ArchiveSpacing.s) {
                    Button {
                        changeMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                    .accessibilityLabel("上一月")
                    .help("查看上一月收支")

                    Text(verbatim: "\(sum.year) 年 \(sum.month) 月 · 收支类目光谱")
                        .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Button {
                        changeMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isCurrentMonthSelected ? ArchivePalette.inkMuted : ArchivePalette.inkSecondary)
                            .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                    .accessibilityLabel("下一月")
                    .help("查看下一月收支")

                    if !isCurrentMonthSelected {
                        Button("回到本月") {
                            let now = FormatUtils.beijingCurrentYearMonth()
                            selectedYear = now.year
                            selectedMonth = now.month
                            visibleTxLimit = 150
                            summaryLoadTask?.cancel()
                            customMonthSummary = nil
                        }
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(ArchivePalette.accentWarm.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(ArchivePalette.accentWarm.opacity(0.35), lineWidth: 0.5)
                        )
                        .paperButtonFocusRing(cornerRadius: 3)
                    }

                    if isLoadingSummary {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Spacer()

                HStack(spacing: ArchiveSpacing.l) {
                    Text("支出 \(FormatUtils.formattedYuan(cents: sum.totalExpense, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    Text("收入 \(FormatUtils.formattedYuan(cents: sum.totalIncome, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(ArchivePalette.accentMoss)
                    Text("结余 \(FormatUtils.formattedYuan(cents: sum.balance, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                }
            }

            ExpenseSpectrumBar(summary: sum, showLegend: true)
        }
        .padding(ArchiveSpacing.l)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 4. 信贷渠道负债明细 & 随身固资货架

    private func channelLiabilitiesSection(_ liabilities: [ChannelLiability]) -> some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            HStack {
                Text("信贷与分期负债渠道 (\(liabilities.count))")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                Text("按各渠道剩余待还与当期应还汇总")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: ArchiveSpacing.m)], spacing: ArchiveSpacing.m) {
                ForEach(liabilities) { ch in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(ch.channelName)
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            Spacer()
                            Text(ch.daysUntilRepayment == 0 ? "今日还款" : "\(ch.daysUntilRepayment) 天后还款")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                .foregroundStyle(ch.daysUntilRepayment <= 3 ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("剩余待还")
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text(FormatUtils.formattedYuan(cents: ch.totalDebt, includeSymbol: true))
                                    .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                    .foregroundStyle(ch.totalDebt > 0 ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("当月应还")
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text(FormatUtils.formattedYuan(cents: ch.monthlyPay, includeSymbol: true))
                                    .font(ArchiveTypography.monoScale(size: 13.5, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                            }
                        }

                        Text("每月 \(ch.repaymentDay) 日出账还款 · 在供 \(ch.activeCount) 笔")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .padding(ArchiveCardMetrics.padding)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                    )
                }
            }
        }
    }

    private func gearAssetsHeaderSection(gearCount: Int) -> some View {
        HStack {
            Text("随身器物与桌面固资 (\(gearCount) 件)")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Spacer()
            Text("服役中的固资将实时计入总资产大盘")
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
    }

    private var gearEmptyState: some View {
        ArchiveEmptyState(
            systemName: ArchiveIcon.gear.systemName,
            title: "尚未登记任何随身器物",
            message: "把相机、镜头、键盘等长期在役的设备登记进来，即可自动计入净资产大盘。",
            primaryTitle: "添置随身设备",
            primaryAction: { showAddGearSheet = true }
        )
    }

    private func gearGrid(_ gearList: [GearItem]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(gearList) { gear in
                GearAssetCardView(
                    gear: gear,
                    onSell: { sellingGear = $0 },
                    onDelete: { g in
                        appState.askConfirm(
                            title: ArchiveSharedCopy.gearDeleteTitle,
                            message: ArchiveSharedCopy.gearDeleteMessage,
                            confirmText: ArchiveSharedCopy.gearDeleteConfirmText,
                            danger: true
                        ) {
                            deleteGear(g)
                        }
                    }
                )
            }
        }
    }

    // MARK: - 5. 流水列表

    private func transactionsHeaderSection(categories: [String], transactionCount: Int) -> some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            HStack {
                Text("流水账目明细 (\(transactionCount) 笔)")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    PaperPillButton(
                        title: "\(selectedMonth)月流水",
                        isSelected: filterBySelectedMonth,
                        isCompact: true
                    ) {
                        filterBySelectedMonth = true
                        visibleTxLimit = 150
                    }
                    PaperPillButton(
                        title: "全部历史",
                        isSelected: !filterBySelectedMonth,
                        isCompact: true
                    ) {
                        filterBySelectedMonth = false
                        visibleTxLimit = 150
                    }

                    Rectangle()
                        .fill(ArchivePalette.borderSubtle)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 3)

                    PaperPillButton(title: "全部类目", isSelected: selectedCategoryFilter == "全部", isCompact: true) {
                        selectedCategoryFilter = "全部"
                        visibleTxLimit = 150
                    }
                    ForEach(categories, id: \.self) { cat in
                        PaperPillButton(title: cat, isSelected: selectedCategoryFilter == cat, isCompact: true) {
                            selectedCategoryFilter = cat
                            visibleTxLimit = 150
                        }
                    }
                }
                .padding(.vertical, ArchiveSpacing.xxs)
            }
            .horizontalFadeMask()
        }
    }

    private var transactionsEmptyState: some View {
        ArchiveEmptyState(
            systemName: ArchiveIcon.ledger.systemName,
            title: "尚无账目流水记录",
            message: "可在上方控制台或菜单栏极速记账面板随时记录每一笔真实花销。",
            primaryTitle: "记第一笔账",
            primaryAction: { showVisualForm = true }
        )
    }

    private func transactionsList(_ transactions: [Transaction]) -> some View {
        let windowed = filterBySelectedMonth ? transactions : Array(transactions.prefix(visibleTxLimit))
        let hasMore = !filterBySelectedMonth && transactions.count > windowed.count

        return LazyVStack(spacing: ArchiveSpacing.s) {
            ForEach(windowed) { tx in
                transactionRow(tx)
            }

            if hasMore {
                Button {
                    visibleTxLimit += 150
                } label: {
                    Text("继续展开更多历史流水（已展示 \(windowed.count) / \(transactions.count) 笔）")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ArchiveSpacing.s)
                }
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                .onAppear {
                    if visibleTxLimit < transactions.count {
                        visibleTxLimit += 150
                    }
                }
            }
        }
    }

    private func transactionRow(_ tx: Transaction) -> some View {
        let syncState = tx.syncStatus ?? "synced"
        return HStack(spacing: ArchiveSpacing.m) {
            Circle()
                .fill(ArchivePalette.categoryColor(for: tx.category))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tx.title.isEmpty ? tx.category : tx.title)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Text(tx.category)
                        .font(ArchiveTypography.bodySans(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    if let badge = tx.installmentBadgeText {
                        Text(badge)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(ArchivePalette.accentWarm, lineWidth: 0.5)
                            )
                    }

                    if syncState == "failed" {
                        HStack(spacing: 4) {
                            Text("同步失败")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                .foregroundStyle(ArchivePalette.accentWarm)
                            Button("重试") {
                                appState.retryFailedTransaction(id: tx.id)
                            }
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro, weight: .semibold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .buttonStyle(.plain)
                            .paperButtonFocusRing(cornerRadius: 2)
                        }
                    } else if syncState != "synced" {
                        Text("待同步")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }

                HStack(spacing: ArchiveSpacing.s) {
                    Text(tx.parsedDate.dotDateTime)
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    if let method = tx.paymentMethod, !method.isEmpty {
                        Text("· \(method)")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    if let note = tx.note, !note.isEmpty {
                        Text("· \(note)")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text("\(tx.type == "income" ? "+" : "-")\(FormatUtils.formattedYuan(cents: tx.amount, includeSymbol: true))")
                .font(ArchiveTypography.monoScale(size: 13.5, weight: .semibold))
                .foregroundStyle(tx.type == "income" ? ArchivePalette.accentMoss : ArchivePalette.inkPrimary)

            HStack(spacing: ArchiveSpacing.s) {
                if tx.id > 0 {
                    PaperIconButton(
                        systemName: "pencil",
                        label: "修订此笔账目",
                        help: "修订此笔账目",
                        size: 11.5,
                        tint: ArchivePalette.inkMuted
                    ) {
                        editingTransaction = tx
                    }
                }

                PaperIconButton(
                    systemName: ArchiveIcon.delete.systemName,
                    label: "删除该笔账目",
                    help: "删除该笔账目",
                    size: 11.5,
                    tint: ArchivePalette.inkMuted
                ) {
                    appState.askConfirm(
                        title: ArchiveSharedCopy.transactionDeleteTitle,
                        message: ArchiveSharedCopy.transactionDeleteMessage,
                        confirmText: ArchiveSharedCopy.transactionDeleteConfirmText,
                        danger: true
                    ) {
                        deleteTransaction(tx)
                    }
                }
            }
        }
        .padding(.horizontal, ArchiveCardMetrics.padding)
        .padding(.vertical, 10)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if tx.id > 0 { editingTransaction = tx }
        }
        .contextMenu {
            if tx.id > 0 {
                Button {
                    editingTransaction = tx
                } label: {
                    Label("修订此笔账目", systemImage: "pencil")
                }
            }
            if syncState == "failed" {
                Button {
                    appState.retryFailedTransaction(id: tx.id)
                } label: {
                    Label("重新上传此账目", systemImage: ArchiveIcon.sync.systemName)
                }
            }
            Button(role: .destructive) {
                appState.askConfirm(
                    title: ArchiveSharedCopy.transactionDeleteTitle,
                    message: ArchiveSharedCopy.transactionDeleteMessage,
                    confirmText: ArchiveSharedCopy.transactionDeleteConfirmText,
                    danger: true
                ) {
                    deleteTransaction(tx)
                }
            } label: {
                Label("删除该笔账目", systemImage: ArchiveIcon.delete.systemName)
            }
            Divider()
            Button {
                SecureClipboard.copy(FormatUtils.formattedYuan(cents: tx.amount))
                appState.showTemporaryBanner("已拷贝金额至剪贴板")
            } label: {
                Label("拷贝金额", systemImage: "doc.on.doc")
            }
            Button {
                SecureClipboard.copy(tx.title.isEmpty ? tx.category : tx.title)
                appState.showTemporaryBanner("已拷贝账目摘要至剪贴板")
            } label: {
                Label("拷贝账目摘要", systemImage: "text.quote")
            }
        }
    }

    // MARK: - 弹窗表单

    private var calibrateLiquidBalanceSheet: some View {
        PaperSheetScaffold(
            title: "校准初始流动资金底数",
            subtitle: "设定记账前的储蓄基准底数（元），系统将以此实时核算当前可用流动资金。",
            width: ArchiveSheetWidth.compact,
            isSubmitting: isCalibratingBalance,
            submitTitle: "保存基准 ⌘↩",
            onCancel: {
                showCalibrateBalanceSheet = false
            },
            onSubmit: submitCalibrateBalance
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                TextField("0.00", text: $initialBalanceYuanInput)
                    .textFieldStyle(.plain)
                    .focused($isCalibrateFieldFocused)
                    .font(ArchiveTypography.monoScale(size: 14))
                    .padding(9)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                            .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                    )

                if let errorNotice {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text(errorNotice)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }
            }
        }
        .onAppear {
            isCalibrateFieldFocused = true
        }
    }

    private func submitCalibrateBalance() {
        guard !isCalibratingBalance else { return }
        let cents = FormatUtils.parseYuanToCents(initialBalanceYuanInput) ?? 0
        isCalibratingBalance = true
        errorNotice = nil
        Task { @MainActor in
            defer { isCalibratingBalance = false }
            do {
                try await APIClient.shared.updateInitialLiquidBalance(cents: cents)
                await appState.loadTransactionsAndAssets(forceFull: false)
                showCalibrateBalanceSheet = false
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }

    private var addGearSheetView: some View {
        AddGearSheet(appState: appState) {
            showAddGearSheet = false
        }
    }

    private func editTransactionSheetView(_ tx: Transaction) -> some View {
        EditTransactionSheet(appState: appState, transaction: tx) {
            editingTransaction = nil
        }
    }

    private func sellGearSheetView(_ gear: GearItem) -> some View {
        SellGearSheet(gear: gear) {
            sellingGear = nil
        } onSold: {
            Task { @MainActor in
                await appState.loadTransactionsAndAssets(forceFull: false)
                await appState.loadConfigAndProfile()
            }
        }
    }

    private func deleteTransaction(_ tx: Transaction) {
        appState.deleteTransactionAction(tx)
    }

    private func deleteGear(_ gear: GearItem) {
        Task { @MainActor in
            await appState.deleteGearAction(gear)
        }
    }
}

#Preview("柴米油盐 · 账本与固资") {
    LedgerAssetsView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}
