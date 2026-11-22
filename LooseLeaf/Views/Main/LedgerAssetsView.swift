import SwiftUI
import AppKit

/// 桌面端独立记账与心愿单视图 (LedgerAssetsView)
/// 顶部分段切换「流水 | 心愿单」；流水页签下提供月度收支光谱、双模记账控制台与明细流水，
/// 心愿单页签嵌入 `WishlistView(embedded: true)`，各司独立滚动容器避免嵌套 ScrollView。
@MainActor
public struct LedgerAssetsView: View {
    @Bindable var appState: AppState

    public typealias LedgerSubTab = LooseLeaf.LedgerSubTab

    @State private var showVisualForm: Bool = false

    // 筛选与弹窗
    @State private var selectedYear: Int = FormatUtils.beijingCurrentYearMonth().year
    @State private var selectedMonth: Int = FormatUtils.beijingCurrentYearMonth().month
    @State private var customMonthSummary: TransactionSummary?
    @State private var isLoadingSummary: Bool = false
    @State private var filterBySelectedMonth: Bool = true
    @State private var selectedCategoryFilter: String = "全部"
    @State private var visibleTxLimit: Int = 150
    @State private var editingTransaction: Transaction?
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
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, ArchiveSpacing.xl)
                .padding(.top, ArchiveSpacing.xl)
                .padding(.bottom, ArchiveSpacing.m)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            if appState.navigation.ledgerSubTab == .ledger {
                ledgerScrollContent
            } else {
                WishlistView(appState: appState, embedded: true)
            }
        }
        .sheet(item: $editingTransaction) { tx in
            editTransactionSheetView(tx)
        }
        .overlay(alignment: .top) {
            if let errorNotice {
                errorBanner(text: errorNotice)
            }
        }
    }

    private var ledgerScrollContent: some View {
        let transactions = filteredTransactions
        let categories = allTransactionCategories
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: ArchiveSpacing.l) {
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
            }
            .padding(ArchiveSpacing.xl)
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

    // MARK: - 1. 页眉（含 流水 | 心愿单 分段切换器）

    private var headerSection: some View {
        @Bindable var navigation = appState.navigation
        return HStack(alignment: .center, spacing: ArchiveSpacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("记账")
                    .font(ArchiveTypography.editorialSerif(size: 22, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text(navigation.ledgerSubTab == .ledger
                     ? "日常收支流水与月度类目光谱 · 每一笔花销皆有归处"
                     : "好物 · 旅程 · 里程碑 · 心愿圆满时可联动入账并落墨散页")
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: ArchiveSpacing.m)

            PaperSegmentedControl(
                selection: $navigation.ledgerSubTab,
                items: [
                    PaperSegmentItem(.ledger, title: LedgerSubTab.ledger.rawValue, icon: ArchiveIcon.ledger.systemName),
                    PaperSegmentItem(.wishlist, title: LedgerSubTab.wishlist.rawValue, icon: ArchiveIcon.wishes.systemName)
                ]
            )
            .frame(width: 192)
        }
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

    // MARK: - 3. 流水列表

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

    private func editTransactionSheetView(_ tx: Transaction) -> some View {
        EditTransactionSheet(appState: appState, transaction: tx) {
            editingTransaction = nil
        }
    }

    private func deleteTransaction(_ tx: Transaction) {
        appState.deleteTransactionAction(tx)
    }
}

#if DEBUG
#Preview("记账 · 流水与心愿单") {
    LedgerAssetsView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}
#endif
