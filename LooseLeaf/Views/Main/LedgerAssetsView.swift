import SwiftUI
import AppKit

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
    @State private var showAddGearSheet: Bool = false
    @State private var editingTransaction: Transaction?
    @State private var sellingGear: GearItem?
    @State private var errorNotice: String?
    @State private var summaryLoadTask: Task<Void, Never>?

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
            CalibrateBalanceSheet(appState: appState) {
                showCalibrateBalanceSheet = false
            }
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
                                appState.reuploadTransaction(id: tx.id)
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
                    appState.reuploadTransaction(id: tx.id)
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

#if DEBUG
#Preview("柴米油盐 · 账本与固资") {
    LedgerAssetsView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}
#endif
