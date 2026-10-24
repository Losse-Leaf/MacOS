import SwiftUI

/// 桌面端独立记账与资产管理中枢视图 (LedgerAssetsView)
/// 严格遵循 docs/backend.md §5.3 & §5.3.1 (RC-53 隐私隔离与 Cents 整型精度)
/// 主理人全权管理级别：支持自然语言+可视化双模记账、账目编辑/删除、固资设备增删改与转让回血
@MainActor
public struct LedgerAssetsView: View {
    @Bindable var appState: AppState

    // 快捷自然语言记账
    @State private var quickLine: String = ""
    @State private var showVisualForm: Bool = false

    // 可视化表单状态
    @State private var formType: String = "expense"
    @State private var formAmountYuan: String = ""
    @State private var formTitle: String = ""
    @State private var formCategory: String = "餐饮"
    @State private var formPaymentMethod: String = "微信支付"
    @State private var formNote: String = ""
    @State private var formCityCode: String = ""
    @State private var formCityName: String = ""
    @State private var formOccurredAt: Date = Date()
    @State private var formLinkGear: Bool = false
    @State private var formGearCategory: String = "数码器材"
    @State private var formGearSpec: String = ""
    @State private var formIsInstallment: Bool = false
    @State private var formInstallmentChannelCode: String = "huabei"
    @State private var formInstallmentMonths: Int = 12
    @State private var formRepaymentDay: Int = 10

    // 筛选与弹窗
    @State private var selectedYear: Int = FormatUtils.beijingCurrentYearMonth().year
    @State private var selectedMonth: Int = FormatUtils.beijingCurrentYearMonth().month
    @State private var customMonthSummary: TransactionSummary?
    @State private var isLoadingSummary: Bool = false
    @State private var filterBySelectedMonth: Bool = true
    @State private var selectedCategoryFilter: String = "全部"
    @State private var showCalibrateBalanceSheet: Bool = false
    @State private var showAddGearSheet: Bool = false
    @State private var showCreditChannelsSheet: Bool = false
    @State private var editingTransaction: Transaction?
    @State private var sellingGear: GearItem?
    @State private var initialBalanceYuanInput: String = ""
    @State private var errorNotice: String?
    /// 月份汇总加载任务句柄：切换月份时取消上一轮未完成的请求，避免响应乱序
    @State private var summaryLoadTask: Task<Void, Never>?

    public init(appState: AppState) {
        self.appState = appState
        // 支付方式默认取用户已配置的首选项，未配置时回落微信支付（不再硬编码单一渠道）
        _formPaymentMethod = State(initialValue: appState.paymentMethods.first ?? "微信支付")
    }

    private var availableCreditChannels: [CreditChannel] {
        if !appState.creditChannels.isEmpty {
            return appState.creditChannels
        }
        return [
            CreditChannel(id: 1, code: "huabei", name: "花呗", repaymentDay: 10, isBuiltin: true),
            CreditChannel(id: 2, code: "baitiao", name: "白条", repaymentDay: 15, isBuiltin: true)
        ]
    }

    private var isCurrentMonthSelected: Bool {
        isCurrentMonth(year: selectedYear, month: selectedMonth)
    }

    /// 判断指定年月是否为当前自然月（北京时间）
    private func isCurrentMonth(year: Int, month: Int) -> Bool {
        let now = FormatUtils.beijingCurrentYearMonth()
        return year == now.year && month == now.month
    }

    private var activeSummary: TransactionSummary {
        if isCurrentMonthSelected {
            return appState.transactionSummary
        }
        return customMonthSummary ?? TransactionSummary(year: selectedYear, month: selectedMonth, totalExpense: 0, totalIncome: 0, balance: 0, categoryBreakdown: [:])
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
        reloadSummary(year: y, month: m)
    }

    /// 重新拉取指定月份的收支汇总。
    /// 切换月份前先取消上一轮未完成的请求，杜绝「旧月份响应晚到」覆盖当前月份数据。
    private func reloadSummary(year: Int, month: Int) {
        summaryLoadTask?.cancel()
        summaryLoadTask = Task { @MainActor in
            await loadSummaryForSelectedMonth(year: year, month: month)
        }
    }

    private func loadSummaryForSelectedMonth(year: Int, month: Int) async {
        // 当前月直接使用本地实时汇总，无需请求
        if isCurrentMonth(year: year, month: month) {
            customMonthSummary = nil
            return
        }
        isLoadingSummary = true
        defer { isLoadingSummary = false }
        do {
            let fetched = try await APIClient.shared.fetchTransactionSummary(year: year, month: month)
            try Task.checkCancellation()
            // 一致性校验：请求返回时若用户已切换到别的月份，丢弃本次响应
            guard selectedYear == year, selectedMonth == month else { return }
            customMonthSummary = fetched
        } catch is CancellationError {
            // 已被新的月份切换取代，静默忽略
        } catch {
            guard selectedYear == year, selectedMonth == month else { return }
            errorNotice = "月度汇总加载失败：\(error.localizedDescription)"
        }
    }

    /// 交易流水筛选结果（供视图一次性绑定复用，避免同一份过滤被重复计算多次）
    private var filteredTransactions: [Transaction] {
        var list = appState.transactions
        if filterBySelectedMonth {
            let prefix = String(format: "%04d-%02d", selectedYear, selectedMonth)
            list = list.filter { $0.occurredAt.hasPrefix(prefix) }
        }
        if selectedCategoryFilter != "全部" {
            list = list.filter { $0.category == selectedCategoryFilter }
        }
        return list
    }

    /// 全部可选类目（支出类目在前，收入类目去重补齐）
    private var allTransactionCategories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for category in appState.expenseCategories + appState.incomeCategories where seen.insert(category).inserted {
            result.append(category)
        }
        return result
    }

    public var body: some View {
        // 一次性绑定筛选结果与类目字典，避免同一份计算在 body 内被重复触发
        let transactions = filteredTransactions
        let categories = allTransactionCategories
        let gearList = appState.profile.edcGear

        ScrollView {
            // LazyVStack 作为 ScrollView 的直接子视图，长列表才具备真正的懒加载能力
            LazyVStack(alignment: .leading, spacing: ArchiveSpacing.xl) {
                headerSection

                if let overview = appState.assetsOverview {
                    assetsOverviewGrid(overview)
                }

                monthlySpectrumCard

                // 双模记账控制台
                dualModeComposerCard

                // 账目流水明细 (标题与筛选)
                transactionsHeaderSection(categories: categories, transactionCount: transactions.count)

                // 账目流水明细 (空态或流水列表)
                if transactions.isEmpty {
                    transactionsEmptyState
                } else {
                    transactionsList(transactions)
                }

                // 随身器物固资货架 (标题)
                gearAssetsHeaderSection(gearCount: gearList.count)

                // 随身器物固资货架 (空态或货架网格)
                if gearList.isEmpty {
                    gearEmptyState
                } else {
                    gearGrid(gearList)
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
        .sheet(isPresented: $showCreditChannelsSheet) {
            CreditChannelsManagerSheet(appState: appState) {
                showCreditChannelsSheet = false
            }
        }
        .sheet(item: $editingTransaction) { tx in
            editTransactionSheetView(tx)
        }
        .sheet(item: $sellingGear) { gear in
            sellGearSheetView(gear)
        }
        // 错误提示提升为根层浮层：弹窗内触发的错误同样可见（弹窗自身亦就地渲染一份）
        .overlay(alignment: .top) {
            if let errorNotice {
                errorBanner(text: errorNotice)
            }
        }
    }

    /// 根层错误横幅（浮于内容区顶部，不被滚动列表遮挡）
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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                Text("柴米油盐 · 独立账本与净资产中枢")
                    .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("每一笔收支皆有归处 · 个人净资产与日常流水总览")
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }
            Spacer()

            HStack(spacing: ArchiveSpacing.s) {
                Button {
                    showCreditChannelsSheet = true
                } label: {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Image(systemName: "creditcard")
                        Text("信贷分期渠道")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()

                Button {
                    showAddGearSheet = true
                } label: {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Image(systemName: "plus.circle")
                        Text("添置随身设备")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()

                Button {
                    if let currentInit = appState.assetsOverview?.initialLiquidBalance {
                        initialBalanceYuanInput = FormatUtils.formattedYuan(cents: currentInit)
                    }
                    showCalibrateBalanceSheet = true
                } label: {
                    HStack(spacing: ArchiveSpacing.xs) {
                        Image(systemName: "slider.horizontal.3")
                        Text("校准初始流动资金")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
            }
        }
    }

    // MARK: - 2. 资产大盘四维指标卡片

    private func assetsOverviewGrid(_ overview: AssetsOverview) -> some View {
        // 响应式列数：最小窗口下自动收敛为 2~3 列，避免每列被压到 167pt 以下
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
                            .padding(5)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
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
                            .padding(5)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下一月")
                    .help("查看下一月收支")

                    if !isCurrentMonthSelected {
                        Button("回到本月") {
                            let now = FormatUtils.beijingCurrentYearMonth()
                            selectedYear = now.year
                            selectedMonth = now.month
                            // 取消尚未返回的历史月份请求，避免其覆盖本月实时汇总
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

    // MARK: - 4. 双模记账控制台 (自然语言 + 可视化交互表单)

    private var dualModeComposerCard: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            // 自然语言快速行
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

                if let parsed = FormatUtils.parseQuickLedgerInput(quickLine) {
                    Text("\(parsed.category) · \(FormatUtils.formattedYuan(cents: parsed.amountCents, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: 11.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                Button {
                    submitQuickLine()
                } label: {
                    // 关键：提交中要有守卫。
                    // 全应用其它提交按钮都有 `isSubmitting` 守卫 + ProgressView，
                    // 只有账本页这两个没有 —— 网络往返期间按钮仍可点，
                    // 于是**同一笔账会被 POST 两次**，产生重复流水。
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
                    withAnimation(.easeInOut(duration: 0.2)) {
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

            // 可视化精细记账展开面板
            if showVisualForm {
                Divider().overlay(ArchivePalette.borderDivider)

                VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                    // 收支类型与金额
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
                                .frame(minWidth: 80, idealWidth: 120, maxWidth: 160)
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

                    // 类目选择胶囊
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

                    // 支付方式与属性标记行
                    HStack(spacing: ArchiveSpacing.s) {
                        Text("支付：")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)

                        HStack(spacing: 6) {
                            ForEach(appState.paymentMethods, id: \.self) { pay in
                                PaperPillButton(title: pay, isSelected: formPaymentMethod == pay) {
                                    formPaymentMethod = pay
                                }
                            }
                        }

                        Spacer()

                        // 联动固资与分期复选
                        Toggle("建入固资大盘", isOn: $formLinkGear)
                            .toggleStyle(.paperCheckbox)
                            .font(ArchiveTypography.bodySans(size: 11.5))

                        if formType == "expense" {
                            Toggle("分期付款", isOn: $formIsInstallment)
                                .toggleStyle(.paperCheckbox)
                                .font(ArchiveTypography.bodySans(size: 11.5))
                        }
                    }

                    // 时空要素行 (独立日期、独立时刻与省市点选，告别挤压折行)
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

                    // 固资扩展信息
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

                    // 分期渠道、期数与每月还款日配置
                    if formIsInstallment && formType == "expense" {
                        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
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

                                Button("管理渠道…") {
                                    showCreditChannelsSheet = true
                                }
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .buttonStyle(.plain)
                                .foregroundStyle(ArchivePalette.accentWarm)
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

                                PaperSelect(
                                    selection: $formRepaymentDay,
                                    options: (1...31).map { PaperSelectOption(value: $0, label: "每月 \($0) 日") },
                                    label: "每月还款日："
                                )

                                Spacer()

                                if let totalCents = FormatUtils.parseYuanToCents(formAmountYuan), totalCents > 0 {
                                    let monthlyCents = totalCents / Int64(max(1, formInstallmentMonths))
                                    Text("每期约 \(FormatUtils.formattedYuan(cents: monthlyCents, includeSymbol: true))")
                                        .font(ArchiveTypography.monoScale(size: 11.5, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                }
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

                    // 提交表单按钮行
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
                            // 同上：提交中守卫，避免连点造成重复流水
                            if isSubmittingTx {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("完成记账并入账")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                        .paperButtonFocusRing()
                        .disabled(isSubmittingTx || (FormatUtils.parseYuanToCents(formAmountYuan) ?? 0) <= 0)
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

    // MARK: - 5. 随身器物固资货架 (EDC Gear Management)

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

    /// 固资空态：提供明确的行动召唤（添置随身设备）
    private var gearEmptyState: some View {
        ArchiveEmptyState(
            systemName: ArchiveIcon.gear.systemName,
            title: "尚未登记任何随身器物",
            message: "把相机、镜头、键盘等长期在役的设备登记进来，即可自动计入净资产大盘。",
            primaryTitle: "添置随身设备",
            primaryAction: { showAddGearSheet = true }
        )
    }

    /// 固资货架网格（作为 ScrollView 子级渲染，保留懒加载能力）
    private func gearGrid(_ gearList: [GearItem]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(gearList) { gear in
                gearCard(gear)
            }
        }
    }

    private func gearCard(_ gear: GearItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(gear.category)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Spacer()

                Text(gear.status == "sold" ? "已转售回血" : "服役中")
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(gear.status == "sold" ? ArchivePalette.inkMuted : ArchivePalette.accentMoss)
            }

            Text(gear.name)
                .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)

            if let spec = gear.spec, !spec.isEmpty {
                Text(spec)
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .lineLimit(1)
            }

            HStack {
                if let price = gear.priceCents, price > 0 {
                    Text("购入 \(FormatUtils.formattedYuan(cents: price, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                if let sold = gear.soldPriceCents, sold > 0 {
                    Text("回血 \(FormatUtils.formattedYuan(cents: sold, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.accentMoss)
                }

                Spacer()

                if gear.status != "sold" {
                    Button("转售回血") {
                        sellingGear = gear
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .buttonStyle(.plain)
                    .foregroundStyle(ArchivePalette.accentWarm)
                }

                PaperIconButton(
                    systemName: ArchiveIcon.delete.systemName,
                    label: "删除设备",
                    help: "删除设备",
                    size: 10.5,
                    tint: ArchivePalette.inkMuted
                ) {
                    appState.askConfirm(
                        title: ArchiveSharedCopy.gearDeleteTitle,
                        message: ArchiveSharedCopy.gearDeleteMessage,
                        confirmText: ArchiveSharedCopy.gearDeleteConfirmText,
                        danger: true
                    ) {
                        deleteGear(gear)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(ArchiveSpacing.m)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
        .paperHover()
    }

    // MARK: - 6. 流水列表

    /// 流水明细标题行与**单行**紧凑筛选器
    ///
    /// 关键（MC-01）：原先是**两行**筛选 —— 时间维度（本月流水 / 全部历史）
    /// 贴在标题行右侧，类目维度（16 个类目）另起一行。
    /// 两行筛选把流水区**往下推**了整整一行，而上面的资产概览、
    /// 月度光谱、记账控制台已经占了不少纵向空间 ——
    /// 结果「账目明细」这个最常看的东西反而要滚一屏才看得到。
    ///
    /// 现在两个维度合并成**一行**：时间维度在前、一条细竖线分隔、类目维度在后，
    /// 整行可横向滚动（首尾渐隐提示可滚）。语义不变，少占一行。
    private func transactionsHeaderSection(categories: [String], transactionCount: Int) -> some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            // 标题行
            HStack {
                Text("流水账目明细 (\(transactionCount) 笔)")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Spacer()
            }

            // 单行紧凑筛选器：时间维度 ‖ 类目维度
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    // ── 时间维度 ──
                    PaperPillButton(
                        title: "\(selectedMonth)月流水",
                        isSelected: filterBySelectedMonth,
                        isCompact: true
                    ) {
                        filterBySelectedMonth = true
                    }
                    PaperPillButton(
                        title: "全部历史",
                        isSelected: !filterBySelectedMonth,
                        isCompact: true
                    ) {
                        filterBySelectedMonth = false
                    }

                    // 维度分隔：一条细竖线，让「时间」与「类目」不至于混成一锅
                    Rectangle()
                        .fill(ArchivePalette.borderSubtle)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 3)

                    // ── 类目维度 ──
                    PaperPillButton(title: "全部类目", isSelected: selectedCategoryFilter == "全部", isCompact: true) {
                        selectedCategoryFilter = "全部"
                    }
                    ForEach(categories, id: \.self) { cat in
                        PaperPillButton(title: cat, isSelected: selectedCategoryFilter == cat, isCompact: true) {
                            selectedCategoryFilter = cat
                        }
                    }
                }
                .padding(.vertical, ArchiveSpacing.xxs)
            }
            .horizontalFadeMask()
        }
    }

    /// 流水空态：提供明确的行动召唤（记第一笔账）
    private var transactionsEmptyState: some View {
        ArchiveEmptyState(
            systemName: ArchiveIcon.ledger.systemName,
            title: "尚无账目流水记录",
            message: "可在上方控制台或菜单栏极速记账面板随时记录每一笔真实花销。",
            primaryTitle: "记第一笔账",
            primaryAction: { showVisualForm = true }
        )
    }

    /// 流水列表（作为 ScrollView 子级渲染，保留懒加载能力）
    private func transactionsList(_ transactions: [Transaction]) -> some View {
        LazyVStack(spacing: ArchiveSpacing.s) {
            ForEach(transactions) { tx in
                transactionRow(tx)
            }
        }
    }

    private func transactionRow(_ tx: Transaction) -> some View {
        HStack(spacing: ArchiveSpacing.m) {
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

                    if tx.isInstallment == true, let months = tx.installmentMonths, months > 0 {
                        Text("分期 \(months) 期")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
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
                PaperIconButton(
                    systemName: "pencil",
                    label: "修订此笔账目",
                    help: "修订此笔账目",
                    size: 11.5,
                    tint: ArchivePalette.inkMuted
                ) {
                    editingTransaction = tx
                }

                if tx.id > 0 {
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
            editingTransaction = tx
        }
        .contextMenu {
            Button {
                editingTransaction = tx
            } label: {
                Label("修订此笔账目", systemImage: "pencil")
            }
            if tx.id > 0 {
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
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                SecureClipboard.copy(FormatUtils.formattedYuan(cents: tx.amount))
                appState.showTemporaryBanner("已拷贝金额至剪贴板")
            } label: {
                Label("拷贝金额", systemImage: "doc.on.doc")
            }
            Button {
                NSPasteboard.general.clearContents()
                SecureClipboard.copy(tx.title.isEmpty ? tx.category : tx.title)
                appState.showTemporaryBanner("已拷贝账目摘要至剪贴板")
            } label: {
                Label("拷贝账目摘要", systemImage: "text.quote")
            }
        }
    }

    // MARK: - 弹窗表单

    private var calibrateLiquidBalanceSheet: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            Text("校准初始流动资金底数")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Text("设定记账前的储蓄基准底数（元），系统将以此实时核算当前可用流动资金。")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkSecondary)

            TextField("0.00", text: $initialBalanceYuanInput)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 14))
                .padding(9)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                        .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                )

            // 弹窗内就地渲染一份错误提示，避免用户只看到「没反应」
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

            HStack {
                Button("取消") {
                    showCalibrateBalanceSheet = false
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()

                Spacer()

                Button("保存基准") {
                    let cents = FormatUtils.parseYuanToCents(initialBalanceYuanInput) ?? 0
                    Task { @MainActor in
                        do {
                            try await APIClient.shared.updateInitialLiquidBalance(cents: cents)
                            await appState.loadTransactionsAndAssets(forceFull: false)
                            showCalibrateBalanceSheet = false
                        } catch {
                            errorNotice = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
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

    // MARK: - 数据提交处理

    /// 记账提交中（防连点造成重复流水）
    @State private var isSubmittingTx: Bool = false

    /// 极速记账的解析结果（body 里算一次，供预览与按钮可用性共用）
    ///
    /// 关键：类目字典必须**按解析出的收支类型**对应传入（与 QuickLedgerView 同一用法）。
    /// 收支类型由输入自身的正负号决定（「+」前缀 = 收入，其余 = 支出）；
    /// 原先恒传支出类目，于是「+5000 工资」匹配不到收入类目，
    /// 被兜底推断成「其他」，收入记录的分类口径从此失真。
    private var quickParsed: FormatUtils.QuickLedgerParsed? {
        let isIncome = quickLine.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+")
        return FormatUtils.parseQuickLedgerInput(
            quickLine,
            knownCategories: isIncome ? appState.incomeCategories : appState.expenseCategories
        )
    }

    private func submitQuickLine() {
        guard let parsed = quickParsed else { return }
        // 关键：提交期间加守卫，防止连点造成**重复流水**
        guard !isSubmittingTx else { return }
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
        guard let cents = FormatUtils.parseYuanToCents(formAmountYuan), cents > 0 else { return }
        // 同上：提交期间加守卫
        guard !isSubmittingTx else { return }
        isSubmittingTx = true
        errorNotice = nil
        let cleanTitle = formTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? formCategory : cleanTitle
        let isInst = (formType == "expense" && formIsInstallment)
        let months = max(1, formInstallmentMonths)
        let monthlyPay = isInst ? (cents / Int64(months)) : nil

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
                    installmentChannelCode: isInst ? formInstallmentChannelCode : nil,
                    installmentTotalAmount: isInst ? cents : nil,
                    installmentMonths: isInst ? months : nil,
                    installmentMonthlyPay: monthlyPay,
                    installmentRemainMonths: isInst ? months : nil,
                    repaymentDay: isInst ? formRepaymentDay : nil,
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

    private func deleteTransaction(_ tx: Transaction) {
        // 统一走 AppState 的删除入口。
        // 关键：原先这里自己调 API ——
        // 于是「删账目」在时间流卡片有 ⌘Z 撤销与错误横幅，在账本列表却没有。
        // 同一个操作两套体验，用户会以为账本页的删除不能撤销。
        appState.deleteTransactionAction(tx)
    }

    private func deleteGear(_ gear: GearItem) {
        // 走 AppState 的动作：删除后登记 ⌘Z 撤销（误删可以原样找回）
        Task { @MainActor in
            await appState.deleteGearAction(gear)
        }
    }
}

// MARK: - 预览 (Preview)

#Preview("柴米油盐 · 账本与固资") {
    LedgerAssetsView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}
