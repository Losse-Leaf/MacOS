import SwiftUI
import AppKit

/// 桌面端独立记账与心愿单视图 (LedgerAssetsView)
/// 顶部分段切换「流水 | 心愿单」；流水页签下固定顶部单行快记条与可折叠月度收支光谱，
/// 账目明细升级为原生 `Table`（支持列排序、列宽拖拽、多选净额汇总与上下文菜单），
/// 完整收支与分期表单通过原生 `.sheet` (`NewTransactionSheet`) 呈现。
@MainActor
public struct LedgerAssetsView: View {
    @Bindable var appState: AppState

    public typealias LedgerSubTab = LooseLeaf.LedgerSubTab

    @State private var showNewTransactionSheet: Bool = false
    @State private var isSpectrumExpanded: Bool = true

    // 筛选、排序与弹窗
    @State private var selectedYear: Int = FormatUtils.beijingCurrentYearMonth().year
    @State private var selectedMonth: Int = FormatUtils.beijingCurrentYearMonth().month
    @State private var customMonthSummary: TransactionSummary?
    @State private var isLoadingSummary: Bool = false
    @State private var filterBySelectedMonth: Bool = true
    @State private var selectedCategoryFilter: String = "全部"
    @State private var selectedTransactionIds: Set<Transaction.ID> = []
    @State private var sortOrder: [KeyPathComparator<Transaction>] = [
        KeyPathComparator(\.occurredAt, order: .reverse)
    ]
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
        selectedTransactionIds.removeAll()
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

    /// 交易流水筛选结果（严格按北京时间 `parsedDate.dateKey` 自然月过滤，修复 UTC 跨月偏移，并响应工具栏 `.searchable`）
    private var filteredTransactions: [Transaction] {
        var list = appState.transactions
        if filterBySelectedMonth {
            let prefix = String(format: "%04d-%02d", selectedYear, selectedMonth)
            list = list.filter { $0.parsedDate.dateKey.hasPrefix(prefix) }
        }
        if selectedCategoryFilter != "全部" {
            list = list.filter { $0.category == selectedCategoryFilter }
        }
        let q = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty, appState.activeSection == .ledger && appState.navigation.ledgerSubTab == .ledger {
            let lowered = q.lowercased()
            list = list.filter { Self.matchesSearch($0, lowercasedQuery: lowered) }
        }
        return list
    }

    private var sortedTransactions: [Transaction] {
        filteredTransactions.sorted(using: sortOrder)
    }

    nonisolated static func matchesSearch(_ tx: Transaction, lowercasedQuery q: String) -> Bool {
        if q.isEmpty { return true }
        return tx.title.lowercased().contains(q)
            || tx.category.lowercased().contains(q)
            || (tx.note?.lowercased().contains(q) ?? false)
            || (tx.paymentMethod?.lowercased().contains(q) ?? false)
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
                .padding(.top, ArchiveSpacing.m)
                .padding(.bottom, ArchiveSpacing.m)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            if appState.navigation.ledgerSubTab == .ledger {
                ledgerWorkspaceContent
            } else {
                WishlistView(appState: appState, embedded: true)
            }
        }
        .sheet(isPresented: $showNewTransactionSheet) {
            NewTransactionSheet(appState: appState) {
                showNewTransactionSheet = false
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .sheet(item: $editingTransaction) { tx in
            editTransactionSheetView(tx)
                .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .overlay(alignment: .top) {
            if let errorNotice {
                errorBanner(text: errorNotice)
            }
        }
    }

    private var ledgerWorkspaceContent: some View {
        let transactions = sortedTransactions
        let categories = allTransactionCategories
        let selectedRows = transactions.filter { selectedTransactionIds.contains($0.id) }

        return VStack(spacing: ArchiveSpacing.m) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                monthlySpectrumCard

                LedgerComposerCard(
                    appState: appState,
                    errorNotice: $errorNotice
                ) {
                    showNewTransactionSheet = true
                }

                transactionsHeaderSection(categories: categories, transactionCount: transactions.count)
            }
            .padding(.horizontal, ArchiveSpacing.xl)
            .padding(.top, ArchiveSpacing.m)

            if transactions.isEmpty {
                transactionsEmptyState
                    .padding(.horizontal, ArchiveSpacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                transactionsTable(transactions)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if selectedRows.count > 1 {
                multiSelectionBar(for: selectedRows)
                    .padding(.horizontal, ArchiveSpacing.xl)
                    .padding(.bottom, ArchiveSpacing.m)
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

    // MARK: - 1. 页眉（含 流水 | 心愿单 分段切换器）

    private var headerSection: some View {
        @Bindable var navigation = appState.navigation
        return HStack(alignment: .center, spacing: ArchiveSpacing.m) {
            VStack(alignment: .leading, spacing: 3) {
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

    // MARK: - 2. 月度收支光谱卡片（可折叠省高度，汇总完全对齐后端 /transactions/summary）

    private var monthlySpectrumCard: some View {
        let sum = activeSummary
        return VStack(alignment: .leading, spacing: isSpectrumExpanded ? ArchiveSpacing.m : 0) {
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

                    Text(verbatim: "\(sum.year) 年 \(sum.month) 月 · 收支光谱")
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
                            selectedTransactionIds.removeAll()
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

                    PaperIconButton(
                        systemName: isSpectrumExpanded ? "chevron.up" : "chevron.down",
                        label: isSpectrumExpanded ? "收起类目光谱" : "展开类目光谱",
                        size: 10.5,
                        tint: ArchivePalette.inkMuted
                    ) {
                        withAnimation(ArchiveMotion.quick) {
                            isSpectrumExpanded.toggle()
                        }
                    }
                }
            }

            if isSpectrumExpanded {
                ExpenseSpectrumBar(summary: sum, showLegend: true)
            }
        }
        .padding(.horizontal, ArchiveSpacing.l)
        .padding(.vertical, isSpectrumExpanded ? ArchiveSpacing.m : ArchiveSpacing.s)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 3. 流水筛选栏与原生 Table

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
                        selectedTransactionIds.removeAll()
                    }
                    PaperPillButton(
                        title: "全部历史",
                        isSelected: !filterBySelectedMonth,
                        isCompact: true
                    ) {
                        filterBySelectedMonth = false
                        selectedTransactionIds.removeAll()
                    }

                    Rectangle()
                        .fill(ArchivePalette.borderSubtle)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 3)

                    PaperPillButton(title: "全部类目", isSelected: selectedCategoryFilter == "全部", isCompact: true) {
                        selectedCategoryFilter = "全部"
                        selectedTransactionIds.removeAll()
                    }
                    ForEach(categories, id: \.self) { cat in
                        PaperPillButton(title: cat, isSelected: selectedCategoryFilter == cat, isCompact: true) {
                            selectedCategoryFilter = cat
                            selectedTransactionIds.removeAll()
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
            message: "可在上方快记条直接输入「42.5 咖啡」，或打开详细表单录入完整收支与分期。",
            primaryTitle: "记第一笔账",
            primaryAction: { showNewTransactionSheet = true }
        )
    }

    @ViewBuilder
    private func transactionsTable(_ transactions: [Transaction]) -> some View {
        Table(transactions, selection: $selectedTransactionIds, sortOrder: $sortOrder) {
            TableColumn("日期", value: \.occurredAt) { tx in
                Text(tx.parsedDate.dotDateTime)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
            }
            .width(min: 112, ideal: 128, max: 156)

            TableColumn("类目", value: \.category) { tx in
                HStack(spacing: 6) {
                    Circle()
                        .fill(ArchivePalette.categoryColor(for: tx.category))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(tx.category)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .lineLimit(1)
                }
            }
            .width(min: 86, ideal: 106, max: 140)

            TableColumn("摘要", value: \.sortableTitle) { tx in
                transactionSummaryCell(tx)
            }
            .width(min: 180, ideal: 300)

            TableColumn("支付方式") { tx in
                Text(tx.paymentMethod?.isEmpty == false ? tx.paymentMethod! : "—")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
            }
            .width(min: 76, ideal: 96, max: 132)

            TableColumn("金额", value: \.signedAmountForSort) { tx in
                HStack {
                    Spacer(minLength: 0)
                    Text("\(tx.type == "income" ? "+" : "-")\(FormatUtils.formattedYuan(cents: tx.amount, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .semibold))
                        .foregroundStyle(tx.type == "income" ? ArchivePalette.accentMoss : ArchivePalette.inkPrimary)
                }
            }
            .width(min: 98, ideal: 118, max: 150)
        }
        .tableStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(ArchivePalette.archivePaper)
        .contextMenu(forSelectionType: Transaction.ID.self) { ids in
            let rows = transactions.filter { ids.contains($0.id) }
            if rows.count == 1, let tx = rows.first {
                singleTransactionContextMenu(tx)
            } else if rows.count > 1 {
                multiTransactionContextMenu(rows)
            }
        } primaryAction: { ids in
            if ids.count == 1,
               let id = ids.first,
               let tx = transactions.first(where: { $0.id == id }),
               tx.id > 0 {
                editingTransaction = tx
            }
        }
    }

    private func transactionSummaryCell(_ tx: Transaction) -> some View {
        let syncState = tx.syncStatus ?? "synced"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(tx.sortableTitle)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .lineLimit(1)

                if let badge = tx.installmentBadgeText {
                    Text(badge)
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(ArchivePalette.accentWarm, lineWidth: 0.5)
                        )
                }

                if tx.isInstallmentRepayment {
                    let feeText = (tx.feeAmount ?? 0) > 0
                        ? "分期还款 · 息费 \(FormatUtils.formattedYuan(cents: tx.feeAmount ?? 0, includeSymbol: true))"
                        : "分期还款"
                    Text(feeText)
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
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

            if let note = tx.note, !note.isEmpty {
                Text(note)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func singleTransactionContextMenu(_ tx: Transaction) -> some View {
        let syncState = tx.syncStatus ?? "synced"
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
                selectedTransactionIds.remove(tx.id)
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
            SecureClipboard.copy(tx.sortableTitle)
            appState.showTemporaryBanner("已拷贝账目摘要至剪贴板")
        } label: {
            Label("拷贝账目摘要", systemImage: "text.quote")
        }
    }

    @ViewBuilder
    private func multiTransactionContextMenu(_ rows: [Transaction]) -> some View {
        Button {
            copySummary(for: rows)
        } label: {
            Label("拷贝 \(rows.count) 笔汇总明细", systemImage: "doc.on.doc")
        }
        Button(role: .destructive) {
            confirmBatchDelete(rows)
        } label: {
            Label("删除选中的 \(rows.count) 笔账目", systemImage: ArchiveIcon.delete.systemName)
        }
    }

    private func multiSelectionBar(for rows: [Transaction]) -> some View {
        let netCents = rows.reduce(Int64(0)) { $0 + $1.signedAmountForSort }
        let netPrefix = netCents >= 0 ? "+" : "-"
        let netFormatted = "\(netPrefix)\(FormatUtils.formattedYuan(cents: abs(netCents), includeSymbol: true))"

        return HStack(spacing: ArchiveSpacing.m) {
            Text("已选 \(rows.count) 笔 · 净额 \(netFormatted)")
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Spacer()

            Button("拷贝明细") {
                copySummary(for: rows)
            }
            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            .paperButtonFocusRing()

            Button("批量删除") {
                confirmBatchDelete(rows)
            }
            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
            .foregroundStyle(ArchivePalette.accentWarm)
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            .paperButtonFocusRing()

            Button("取消选择") {
                selectedTransactionIds.removeAll()
            }
            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
            .buttonStyle(.plain)
            .foregroundStyle(ArchivePalette.inkMuted)
            .paperButtonFocusRing(cornerRadius: 4)
        }
        .padding(.horizontal, ArchiveCardMetrics.padding)
        .padding(.vertical, ArchiveSpacing.s)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.6)
        )
    }

    private func copySummary(for rows: [Transaction]) {
        let lines = rows.map { tx in
            let sign = tx.type == "income" ? "+" : "-"
            return "\(tx.parsedDate.dotDate)  \(tx.category)  \(tx.sortableTitle)  \(sign)\(FormatUtils.formattedYuan(cents: tx.amount, includeSymbol: true))"
        }
        SecureClipboard.copy(lines.joined(separator: "\n"))
        appState.showTemporaryBanner("已拷贝 \(rows.count) 笔账目明细至剪贴板")
    }

    private func confirmBatchDelete(_ rows: [Transaction]) {
        appState.askConfirm(
            title: "删除选中的 \(rows.count) 笔账目？",
            message: "将逐条提交删除，可在短时间内按 ⌘Z 依次撤销。",
            confirmText: "删除 \(rows.count) 笔",
            danger: true
        ) {
            for tx in rows {
                deleteTransaction(tx)
            }
            selectedTransactionIds.removeAll()
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
