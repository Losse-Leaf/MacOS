import SwiftUI

/// 桌面端独立记账与资产管理中枢视图 (LedgerAssetsView)
/// 严格遵循 docs/backend.md §5.3 & §5.3.1 (RC-53 隐私硬隔离与 Cents 整型精度)
public struct LedgerAssetsView: View {
    @Bindable var appState: AppState

    @State private var quickLine: String = ""
    @State private var selectedCategoryFilter: String = "全部"
    @State private var showCalibrateBalanceSheet: Bool = false
    @State private var initialBalanceYuanInput: String = ""
    @State private var errorNotice: String?

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredTransactions: [Transaction] {
        if selectedCategoryFilter == "全部" {
            return appState.transactions
        }
        return appState.transactions.filter { $0.category == selectedCategoryFilter }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if !appState.isPaired {
                    unpairedPrivacyGate
                } else {
                    if let overview = appState.assetsOverview {
                        assetsOverviewGrid(overview)
                    }

                    monthlySpectrumCard

                    quickEntryBar

                    transactionsListSection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showCalibrateBalanceSheet) {
            calibrateLiquidBalanceSheet
        }
    }

    // MARK: - 页眉

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("柴米油盐 · 独立账本与净资产中枢")
                    .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("金额严格以整型分流转 · 访客模式零感知硬隔离")
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }
            Spacer()
            if appState.isPaired {
                Button {
                    if let currentInit = appState.assetsOverview?.initialLiquidBalance {
                        initialBalanceYuanInput = FormatUtils.formattedYuan(cents: currentInit)
                    }
                    showCalibrateBalanceSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text("校准初始流动资金")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }
        }
    }

    // MARK: - 未配对隐私门控

    private var unpairedPrivacyGate: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(ArchivePalette.accentWarm)
            Text("私密财务账本仅向已授信设备开放")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Text("请先通过 6 位配对码或主理人密钥绑定当前 Mac，解锁资产看板与极速记账能力。")
                .font(ArchiveTypography.bodySans(size: 12.5))
                .foregroundStyle(ArchivePalette.inkSecondary)
            Button("前往设备免密配对") {
                appState.activeSection = .settings
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
    }

    // MARK: - 资产大盘四维指标卡片

    private func assetsOverviewGrid(_ overview: AssetsOverview) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
                subtitle: "随身设备 \(overview.gearSummary?.activeCount ?? 0) 件在役",
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
                .font(ArchiveTypography.monoScale(size: 10))
                .foregroundStyle(ArchivePalette.inkMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 月度收支光谱卡片

    private var monthlySpectrumCard: some View {
        let sum = appState.transactionSummary
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(sum.year) 年 \(sum.month) 月 · 收支类目光谱")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                HStack(spacing: 16) {
                    Text("支出 \(FormatUtils.formattedYuan(cents: sum.totalExpense, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: 12, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    Text("收入 \(FormatUtils.formattedYuan(cents: sum.totalIncome, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: 12))
                        .foregroundStyle(ArchivePalette.accentMoss)
                    Text("结余 \(FormatUtils.formattedYuan(cents: sum.balance, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: 12))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                }
            }

            ExpenseSpectrumBar(summary: sum, showLegend: true)
        }
        .padding(16)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 快捷记账行

    private var quickEntryBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.Viewfinder")
                .foregroundStyle(ArchivePalette.accentWarm)

            TextField("快速记一笔（如：42.5 午餐咖啡 或 +5000 稿费），按 Return 直接入账…", text: $quickLine)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 13))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .onSubmit {
                    submitQuickLine()
                }

            if let parsed = FormatUtils.parseQuickLedgerInput(quickLine) {
                Text("\(parsed.category) · \(FormatUtils.formattedYuan(cents: parsed.amountCents, includeSymbol: true))")
                    .font(ArchiveTypography.monoScale(size: 11.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            Button("记入账本") {
                submitQuickLine()
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .disabled(FormatUtils.parseQuickLedgerInput(quickLine) == nil)
        }
        .padding(12)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
    }

    // MARK: - 流水列表

    private var transactionsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    PaperPillButton(title: "全部", isSelected: selectedCategoryFilter == "全部") {
                        selectedCategoryFilter = "全部"
                    }
                    ForEach(appState.expenseCategories, id: \.self) { cat in
                        PaperPillButton(title: cat, isSelected: selectedCategoryFilter == cat) {
                            selectedCategoryFilter = cat
                        }
                    }
                }
            }

            if let errorNotice {
                Text(errorNotice)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            if filteredTransactions.isEmpty {
                VStack(spacing: 8) {
                    Text("尚无账目流水记录")
                        .font(ArchiveTypography.editorialSerif(size: 14))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Text("可在上方输入框或菜单栏极速记账面板随时记录每一笔真实花销")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredTransactions) { tx in
                        transactionRow(tx)
                    }
                }
            }
        }
    }

    private func transactionRow(_ tx: Transaction) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ArchivePalette.categoryColor(for: tx.category))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tx.title.isEmpty ? tx.category : tx.title)
                        .font(ArchiveTypography.bodySans(size: 13, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Text(tx.category)
                        .font(ArchiveTypography.bodySans(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    if tx.isInstallment == true, let months = tx.installmentMonths, months > 0 {
                        Text("分期 \(months) 期")
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(ArchivePalette.accentWarm, lineWidth: 0.5)
                            )
                    }

                    if (tx.syncStatus ?? "synced") != "synced" {
                        Text("待同步")
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }

                HStack(spacing: 8) {
                    Text(tx.parsedDate.dotDateTime)
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    if let method = tx.paymentMethod, !method.isEmpty {
                        Text("· \(method)")
                            .font(ArchiveTypography.bodySans(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    if let note = tx.note, !note.isEmpty {
                        Text("· \(note)")
                            .font(ArchiveTypography.bodySans(size: 11))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text("\(tx.type == "income" ? "+" : "-")\(FormatUtils.formattedYuan(cents: tx.amount, includeSymbol: true))")
                .font(ArchiveTypography.monoScale(size: 13.5, weight: .semibold))
                .foregroundStyle(tx.type == "income" ? ArchivePalette.accentMoss : ArchivePalette.inkPrimary)

            if tx.id > 0 {
                Button {
                    deleteTransaction(tx)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .buttonStyle(.plain)
                .help("删除该笔账目")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 校准初始流动资金弹窗

    private var calibrateLiquidBalanceSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("校准初始流动资金底数")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Text("设定开始记账前的储蓄水位基线（元），系统将自动按整型分持久化并实时重算可用余额。")
                .font(ArchiveTypography.bodySans(size: 12))
                .foregroundStyle(ArchivePalette.inkSecondary)

            TextField("例如：50000.00", text: $initialBalanceYuanInput)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 14))
                .padding(9)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                )

            HStack {
                Button("取消") {
                    showCalibrateBalanceSheet = false
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                Spacer()

                Button("保存基准") {
                    let cents = FormatUtils.parseYuanToCents(initialBalanceYuanInput) ?? 0
                    Task {
                        try? await APIClient.shared.updateInitialLiquidBalance(cents: cents)
                        await appState.loadTransactionsAndAssets(forceFull: true)
                        showCalibrateBalanceSheet = false
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(ArchivePalette.archivePaper)
    }

    private func submitQuickLine() {
        guard let parsed = FormatUtils.parseQuickLedgerInput(quickLine) else { return }
        errorNotice = nil
        Task {
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

    private func deleteTransaction(_ tx: Transaction) {
        Task {
            do {
                try await APIClient.shared.deleteTransaction(id: tx.id)
                await appState.loadTransactionsAndAssets(forceFull: true)
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }
}
