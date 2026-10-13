import SwiftUI

/// 桌面端独立记账与资产管理中枢视图 (LedgerAssetsView)
/// 严格遵循 docs/backend.md §5.3 & §5.3.1 (RC-53 隐私隔离与 Cents 整型精度)
/// 主理人全权管理级别：支持自然语言+可视化双模记账、账目编辑/删除、固资设备增删改与转让回血
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
    @State private var formLinkGear: Bool = false
    @State private var formGearCategory: String = "数码器材"
    @State private var formGearSpec: String = ""
    @State private var formIsInstallment: Bool = false
    @State private var formInstallmentMonths: Int = 12

    // 筛选与弹窗
    @State private var selectedCategoryFilter: String = "全部"
    @State private var showCalibrateBalanceSheet: Bool = false
    @State private var showAddGearSheet: Bool = false
    @State private var editingTransaction: Transaction?
    @State private var sellingGear: GearItem?
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

                if let overview = appState.assetsOverview {
                    assetsOverviewGrid(overview)
                }

                monthlySpectrumCard

                // 双模记账控制台
                dualModeComposerCard

                // 随身器物固资货架
                gearAssetsSection

                // 账目流水明细
                transactionsListSection
            }
            .padding(24)
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
    }

    // MARK: - 1. 页眉

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("柴米油盐 · 独立账本与净资产中枢")
                    .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("金额严格以整型分流转 · 主理人全权管理与资产大盘")
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }
            Spacer()

            HStack(spacing: 8) {
                Button {
                    showAddGearSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("添置随身设备")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

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

    // MARK: - 2. 资产大盘四维指标卡片

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

    // MARK: - 3. 月度收支光谱卡片

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

    // MARK: - 4. 双模记账控制台 (自然语言 + 可视化交互表单)

    private var dualModeComposerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 自然语言快速行
            HStack(spacing: 10) {
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 14))
                    .foregroundStyle(ArchivePalette.accentWarm)

                TextField("快速指令（如：42.5 午餐咖啡 或 +5000 稿费），按 Return 直接入账…", text: $quickLine)
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

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showVisualForm.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showVisualForm ? "chevron.up.circle.fill" : "slider.horizontal.below.rectangle")
                        Text(showVisualForm ? "收起表单" : "可视化表单")
                    }
                    .font(ArchiveTypography.bodySans(size: 11.5))
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            // 可视化精细记账展开面板
            if showVisualForm {
                Divider().overlay(ArchivePalette.borderDivider)

                VStack(alignment: .leading, spacing: 12) {
                    // 收支类型与金额
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            PaperPillButton(title: "支出", isSelected: formType == "expense") {
                                formType = "expense"
                                AudioFeedback.shared.playTink()
                            }
                            PaperPillButton(title: "收入", isSelected: formType == "income") {
                                formType = "income"
                                AudioFeedback.shared.playTink()
                            }
                        }

                        HStack(spacing: 4) {
                            Text("¥")
                                .font(ArchiveTypography.monoScale(size: 13, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkMuted)
                            TextField("0.00", text: $formAmountYuan)
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.monoScale(size: 13.5, weight: .semibold))
                                .frame(width: 80)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                        )

                        TextField("账目说明/标题（如：数码器材、春季外卖）", text: $formTitle)
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.bodySans(size: 12.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                            )
                    }

                    // 类目选择胶囊
                    HStack(alignment: .top, spacing: 8) {
                        Text("类目：")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(.top, 4)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(appState.expenseCategories, id: \.self) { cat in
                                    PaperPillButton(title: cat, isSelected: formCategory == cat) {
                                        formCategory = cat
                                        AudioFeedback.shared.playTink()
                                    }
                                }
                            }
                        }
                    }

                    // 支付方式
                    HStack(spacing: 8) {
                        Text("支付：")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)

                        HStack(spacing: 6) {
                            ForEach(appState.paymentMethods, id: \.self) { pay in
                                PaperPillButton(title: pay, isSelected: formPaymentMethod == pay) {
                                    formPaymentMethod = pay
                                    AudioFeedback.shared.playTink()
                                }
                            }
                        }

                        Spacer()

                        // 联动固资与分期复选
                        Toggle("建入固资大盘", isOn: $formLinkGear)
                            .toggleStyle(.checkbox)
                            .font(ArchiveTypography.bodySans(size: 11.5))

                        Toggle("分期付款", isOn: $formIsInstallment)
                            .toggleStyle(.checkbox)
                            .font(ArchiveTypography.bodySans(size: 11.5))
                    }

                    // 固资扩展信息
                    if formLinkGear {
                        HStack(spacing: 8) {
                            TextField("固资分类（如：数码摄影、桌面办公）", text: $formGearCategory)
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.bodySans(size: 12))
                                .padding(6)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            TextField("固资规格说明（如：M3 Max / 36GB / 1TB）", text: $formGearSpec)
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.bodySans(size: 12))
                                .padding(6)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    // 分期期数
                    if formIsInstallment {
                        HStack(spacing: 8) {
                            Text("分期期数：")
                                .font(ArchiveTypography.bodySans(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkMuted)

                            ForEach([3, 6, 12, 24], id: \.self) { months in
                                PaperPillButton(title: "\(months) 期", isSelected: formInstallmentMonths == months) {
                                    formInstallmentMonths = months
                                }
                            }
                        }
                    }

                    // 提交表单按钮行
                    HStack {
                        TextField("附加备注手记（可选）", text: $formNote)
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.bodySans(size: 12))
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Button("一键精准入账") {
                            submitVisualForm()
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                        .disabled((FormatUtils.parseYuanToCents(formAmountYuan) ?? 0) <= 0)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
    }

    // MARK: - 5. 随身器物固资货架 (EDC Gear Management)

    private var gearAssetsSection: some View {
        let gearList = appState.profile.edcGear
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("随身器物与桌面固资 (\(gearList.count) 件)")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                Text("服役中的固资将实时计入总资产大盘")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            if gearList.isEmpty {
                Text("暂无随身器材记录，可在记账时勾选「建入固资大盘」或点击右上角「添置随身设备」。")
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(gearList) { gear in
                        gearCard(gear)
                    }
                }
            }
        }
    }

    private func gearCard(_ gear: GearItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(gear.category)
                    .font(ArchiveTypography.monoScale(size: 10))
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
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                if let sold = gear.soldPriceCents, sold > 0 {
                    Text("回血 \(FormatUtils.formattedYuan(cents: sold, includeSymbol: true))")
                        .font(ArchiveTypography.monoScale(size: 11))
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

                Button {
                    deleteGear(gear)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .buttonStyle(.plain)
                .help("删除设备")
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 6. 流水列表

    private var transactionsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("流水账目明细 (\(appState.transactions.count) 笔)")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Spacer()

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
                    Text("可在上方控制台或菜单栏极速记账面板随时记录每一笔真实花销")
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

            HStack(spacing: 8) {
                Button {
                    editingTransaction = tx
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .buttonStyle(.plain)
                .help("修订此笔账目")

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

    // MARK: - 弹窗表单

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
            Task {
                await appState.loadTransactionsAndAssets(forceFull: true)
                await appState.loadConfigAndProfile()
            }
        }
    }

    // MARK: - 数据提交处理

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

    private func submitVisualForm() {
        guard let cents = FormatUtils.parseYuanToCents(formAmountYuan), cents > 0 else { return }
        errorNotice = nil
        let cleanTitle = formTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? formCategory : cleanTitle

        Task {
            do {
                let req = CreateTransactionRequest(
                    amount: cents,
                    type: formType,
                    category: formCategory,
                    title: finalTitle,
                    note: formNote.isEmpty ? nil : formNote,
                    paymentMethod: formPaymentMethod,
                    occurredAt: FormatUtils.beijingISOString(),
                    isInstallment: formIsInstallment,
                    installmentMonths: formIsInstallment ? formInstallmentMonths : nil,
                    linkGearAsset: formLinkGear,
                    gearCategory: formLinkGear ? formGearCategory : nil,
                    gearSpec: formLinkGear ? formGearSpec : nil
                )
                _ = try await SyncManager.shared.submitTransaction(req)
                AudioFeedback.shared.playShutter()
                formAmountYuan = ""
                formTitle = ""
                formNote = ""
                formLinkGear = false
                formIsInstallment = false
                await appState.loadTransactionsAndAssets(forceFull: true)
                await appState.loadConfigAndProfile()
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }

    private func deleteTransaction(_ tx: Transaction) {
        Task {
            do {
                try await APIClient.shared.deleteTransaction(id: tx.id)
                AudioFeedback.shared.playTink()
                await appState.loadTransactionsAndAssets(forceFull: true)
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }

    private func deleteGear(_ gear: GearItem) {
        Task {
            do {
                try await APIClient.shared.deleteGearAsset(id: gear.id)
                AudioFeedback.shared.playTink()
                await appState.loadConfigAndProfile()
                await appState.loadTransactionsAndAssets(forceFull: true)
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }
}

// MARK: - 独立弹窗组件：修订流水 (EditTransactionSheet)

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
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, transaction: Transaction, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.transaction = transaction
        self.onDismiss = onDismiss
        _type = State(initialValue: transaction.type)
        _amountYuan = State(initialValue: FormatUtils.formattedYuan(cents: transaction.amount))
        _title = State(initialValue: transaction.title)
        _category = State(initialValue: transaction.category)
        _paymentMethod = State(initialValue: transaction.paymentMethod ?? "微信支付")
        _note = State(initialValue: transaction.note ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("修订流水账目")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 8) {
                PaperPillButton(title: "支出", isSelected: type == "expense") { type = "expense" }
                PaperPillButton(title: "收入", isSelected: type == "income") { type = "income" }

                HStack(spacing: 4) {
                    Text("¥")
                        .font(ArchiveTypography.monoScale(size: 13, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    TextField("0.00", text: $amountYuan)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                        .frame(width: 80)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            TextField("账目名称 / 摘要", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 6) {
                Text("类目选择")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(appState.expenseCategories, id: \.self) { cat in
                            PaperPillButton(title: cat, isSelected: category == cat) { category = cat }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("支付方式")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                HStack(spacing: 6) {
                    ForEach(appState.paymentMethods, id: \.self) { pay in
                        PaperPillButton(title: pay, isSelected: paymentMethod == pay) { paymentMethod = pay }
                    }
                }
            }

            TextField("补充备注手记", text: $note)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存修订") {
                    saveChanges()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(isSubmitting || (FormatUtils.parseYuanToCents(amountYuan) ?? 0) <= 0)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(ArchivePalette.archivePaper)
    }

    private func saveChanges() {
        guard let cents = FormatUtils.parseYuanToCents(amountYuan), cents > 0 else { return }
        isSubmitting = true
        errorText = nil
        Task {
            do {
                let req = CreateTransactionRequest(
                    amount: cents,
                    type: type,
                    category: category,
                    title: title.isEmpty ? category : title,
                    note: note.isEmpty ? nil : note,
                    paymentMethod: paymentMethod,
                    occurredAt: transaction.occurredAt
                )
                _ = try await APIClient.shared.updateTransaction(id: transaction.id, req)
                AudioFeedback.shared.playShutter()
                await appState.loadTransactionsAndAssets(forceFull: true)
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 独立弹窗组件：添置随身设备 (AddGearSheet)

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

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添置随身器物与在役固资")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("设备名称（如：Sony A7C2 相机、HHKB 键盘）", text: $name)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("规格参数（如：单机身银色、Type-S 静音版）", text: $spec)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 8) {
                TextField("器物分类（如：摄影器材、生活物件）", text: $category)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                TextField("购入金额（元）", text: $priceYuan)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: 13))
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Toggle("伴生记录一笔支出流水", isOn: $createTransaction)
                .toggleStyle(.checkbox)
                .font(ArchiveTypography.bodySans(size: 12))

            TextField("器物手记/初衷", text: $note)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("添置并纳入大盘") {
                    submitAddGear()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(ArchivePalette.archivePaper)
    }

    private func submitAddGear() {
        let cents = FormatUtils.parseYuanToCents(priceYuan) ?? 0
        isSubmitting = true
        errorText = nil
        Task {
            do {
                let req = AddGearAssetRequest(
                    name: name,
                    spec: spec.isEmpty ? nil : spec,
                    category: category,
                    priceCents: cents,
                    purchaseDate: FormatUtils.beijingDateString(),
                    note: note.isEmpty ? nil : note,
                    createTransaction: createTransaction,
                    paymentMethod: paymentMethod
                )
                _ = try await APIClient.shared.addGearAsset(req)
                AudioFeedback.shared.playShutter()
                await appState.loadConfigAndProfile()
                await appState.loadTransactionsAndAssets(forceFull: true)
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 独立弹窗组件：转让回血 (SellGearSheet)

public struct SellGearSheet: View {
    let gear: GearItem
    var onDismiss: () -> Void
    var onSold: () -> Void

    @State private var soldPriceYuan: String = ""
    @State private var note: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("出闲置 · 转售器材回血")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text("转让设备：\(gear.name) (\(gear.spec ?? gear.category))")
                .font(ArchiveTypography.bodySans(size: 13, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)

            if let boughtPrice = gear.priceCents, boughtPrice > 0 {
                Text("原购入成本：\(FormatUtils.formattedYuan(cents: boughtPrice, includeSymbol: true))")
                    .font(ArchiveTypography.monoScale(size: 12))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            TextField("实际转售回血金额（元，如：3200.00）", text: $soldPriceYuan)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 14))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("转让交接随笔手记（如：闲鱼面交出给同城摄友）", text: $note)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("确认转售归档") {
                    submitSell()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(isSubmitting || (FormatUtils.parseYuanToCents(soldPriceYuan) ?? 0) <= 0)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(ArchivePalette.archivePaper)
    }

    private func submitSell() {
        guard let cents = FormatUtils.parseYuanToCents(soldPriceYuan), cents > 0 else { return }
        isSubmitting = true
        errorText = nil
        Task {
            do {
                let req = SellGearRequest(
                    soldPriceCents: cents,
                    soldDate: FormatUtils.beijingDateString(),
                    note: note.isEmpty ? nil : note
                )
                _ = try await APIClient.shared.sellGearAsset(id: gear.id, req)
                AudioFeedback.shared.playShutter()
                onSold()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
