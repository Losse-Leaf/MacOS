import SwiftUI

/// 心愿清单独立主视图 (WishlistView)
/// 严格 1:1 对标 Web 端 `web/src/components/WishlistView.vue`：
/// 1. 标头：“心愿清单 · 好物 · 旅程 · 里程碑” + “许下心愿”快捷入口
/// 2. 顶部三列大盘指标卡：在愿向往（预算 ¥）、圆满达成（投入 ¥）、理性拔草（省下 ¥）
/// 3. 双级过滤胶囊：维度（全维度/好物/旅程/里程碑）与状态（向往中/圆满达成/理性拔草/全部）
/// 4. 心愿网格卡片与圆满达成归册仪式 (WishResolutionSheet)
@MainActor
public struct WishlistView: View {
    @Bindable var appState: AppState

    @State private var selectedKind: String = "all" // all, item, travel, milestone
    @State private var selectedStatus: String = "wanting" // wanting, fulfilled, relinquished, all

    @State private var showNewWishSheet: Bool = false
    @State private var editingWish: Wish?
    @State private var resolvingWish: Wish?
    @State private var errorMessage: String?

    public init(appState: AppState) {
        self.appState = appState
    }

    // 统计大盘计算属性 (基于全量心愿)
    private var allWishes: [Wish] { appState.wishes }

    private var wantingWishes: [Wish] {
        allWishes.filter { $0.status == "wanting" }
    }

    private var fulfilledWishes: [Wish] {
        allWishes.filter { $0.status == "fulfilled" }
    }

    private var relinquishedWishes: [Wish] {
        allWishes.filter { $0.status == "relinquished" }
    }

    private var totalWantingBudgetCents: Int64 {
        wantingWishes.reduce(Int64(0)) { $0 + $1.budget }
    }

    private var totalFulfilledSpentCents: Int64 {
        fulfilledWishes.reduce(Int64(0)) { $0 + ($1.actualCost > 0 ? $1.actualCost : $1.budget) }
    }

    private var totalSavedBudgetCents: Int64 {
        relinquishedWishes.reduce(Int64(0)) { $0 + $1.budget }
    }

    // 过滤后展示的心愿列表
    private var filteredWishes: [Wish] {
        allWishes.filter { wish in
            let matchKind = (selectedKind == "all") || (wish.kind == selectedKind)
            let matchStatus = (selectedStatus == "all") || (wish.status == selectedStatus)
            return matchKind && matchStatus
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                statisticsCardsSection

                filterPillsSection

                if let err = errorMessage {
                    Text(err)
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                if filteredWishes.isEmpty {
                    emptyPlaceholder
                } else {
                    wishesGridSection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showNewWishSheet) {
            NewWishSheet(appState: appState) {
                showNewWishSheet = false
            }
        }
        .sheet(item: $editingWish) { wish in
            EditWishSheet(appState: appState, wish: wish) {
                editingWish = nil
            }
        }
        .sheet(item: $resolvingWish) { wish in
            ResolveWishSheet(appState: appState, wish: wish) {
                resolvingWish = nil
            }
        }
    }

    // MARK: - 1. 标头
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Text("心愿清单")
                        .font(ArchiveTypography.editorialSerif(size: 24, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("好物 · 旅程 · 里程碑")
                        .font(ArchiveTypography.monoScale(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Spacer()

                Button {
                    showNewWishSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("许下心愿")
                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }

            Text("生活的三维期冀：花钱可得的称手好物、需要闲暇与决心的山川行旅、心智进阶的人生里程碑。无截止死线，真实倒映生活向往。")
                .font(ArchiveTypography.editorialSerif(size: 12))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .lineSpacing(3)
        }
    }

    // MARK: - 2. 统计大盘三列纸卡
    private var statisticsCardsSection: some View {
        HStack(spacing: 14) {
            statCard(
                title: "在愿向往 (进行中)",
                count: "\(wantingWishes.count) 项",
                subText: totalWantingBudgetCents > 0 ? "预算 ¥\(FormatUtils.formattedYuan(cents: totalWantingBudgetCents, includeSymbol: false))" : nil,
                accentColor: ArchivePalette.inkPrimary
            )

            statCard(
                title: "圆满达成 (已归册)",
                count: "\(fulfilledWishes.count) 项",
                subText: totalFulfilledSpentCents > 0 ? "投入 ¥\(FormatUtils.formattedYuan(cents: totalFulfilledSpentCents, includeSymbol: false))" : nil,
                accentColor: ArchivePalette.accentMoss
            )

            statCard(
                title: "理性拔草 (已释怀)",
                count: "\(relinquishedWishes.count) 项",
                subText: totalSavedBudgetCents > 0 ? "省下 ¥\(FormatUtils.formattedYuan(cents: totalSavedBudgetCents, includeSymbol: false))" : nil,
                accentColor: ArchivePalette.accentWarm
            )
        }
    }

    private func statCard(title: String, count: String, subText: String?, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ArchiveTypography.monoScale(size: 10.5))
                .foregroundStyle(ArchivePalette.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(count)
                    .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                    .foregroundStyle(accentColor)
                if let sub = subText {
                    Text("(\(sub))")
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
    }

    // MARK: - 3. 双级筛选胶囊
    private var filterPillsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 维度 Tab
            HStack(spacing: 6) {
                PaperPillButton(title: "全维度 (\(allWishes.count))", isSelected: selectedKind == "all") {
                    guard selectedKind != "all" else { return }
                    selectedKind = "all"
                }
                PaperPillButton(title: "好物器物 (\(allWishes.filter { $0.kind == "item" }.count))", isSelected: selectedKind == "item") {
                    guard selectedKind != "item" else { return }
                    selectedKind = "item"
                }
                PaperPillButton(title: "行旅探索 (\(allWishes.filter { $0.kind == "travel" }.count))", isSelected: selectedKind == "travel") {
                    guard selectedKind != "travel" else { return }
                    selectedKind = "travel"
                }
                PaperPillButton(title: "阶段进阶 (\(allWishes.filter { $0.kind == "milestone" }.count))", isSelected: selectedKind == "milestone") {
                    guard selectedKind != "milestone" else { return }
                    selectedKind = "milestone"
                }
            }

            // 状态 Tab
            HStack(spacing: 6) {
                PaperPillButton(title: "向往中 (\(wantingWishes.count))", isSelected: selectedStatus == "wanting") {
                    guard selectedStatus != "wanting" else { return }
                    selectedStatus = "wanting"
                }
                PaperPillButton(title: "已圆满 (\(fulfilledWishes.count))", isSelected: selectedStatus == "fulfilled") {
                    guard selectedStatus != "fulfilled" else { return }
                    selectedStatus = "fulfilled"
                }
                PaperPillButton(title: "已拔草 (\(relinquishedWishes.count))", isSelected: selectedStatus == "relinquished") {
                    guard selectedStatus != "relinquished" else { return }
                    selectedStatus = "relinquished"
                }
                PaperPillButton(title: "全部 (\(allWishes.count))", isSelected: selectedStatus == "all") {
                    guard selectedStatus != "all" else { return }
                    selectedStatus = "all"
                }
            }
        }
    }

    // MARK: - 4. 网格卡片
    private var wishesGridSection: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            ForEach(filteredWishes) { wish in
                WishCardView(
                    wish: wish,
                    onResolve: {
                        resolvingWish = wish
                    },
                    onEdit: {
                        editingWish = wish
                    },
                    onDelete: {
                        appState.askConfirm(
                            title: "确认删除该心愿？",
                            message: "删除后该心愿将永久移除，此操作不可恢复。",
                            confirmText: "删除心愿",
                            danger: true
                        ) {
                            deleteWish(wish)
                        }
                    }
                )
            }
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Text("该筛选维度下尚无心愿条目")
                .font(ArchiveTypography.editorialSerif(size: 14, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)
            Text("记下一件心仪器物、一处远方山川或一项阶段进阶目标")
                .font(ArchiveTypography.bodySans(size: 11.5))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func deleteWish(_ wish: Wish) {
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteWish(id: wish.id)
                await appState.loadProjectsWishesFootprints()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
