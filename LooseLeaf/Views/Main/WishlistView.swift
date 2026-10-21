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

    /// 心愿统计快照：一次扫描同时得出各类计数与金额合计，
    /// 供顶部统计卡与筛选胶囊共用，避免同一份数据被反复全量过滤。
    private struct WishStatistics {
        var total: Int = 0
        var wantingCount: Int = 0
        var fulfilledCount: Int = 0
        var relinquishedCount: Int = 0
        var kindCounts: [String: Int] = [:]
        var wantingBudgetCents: Int64 = 0
        var fulfilledSpentCents: Int64 = 0
        var relinquishedSavedCents: Int64 = 0
    }

    private func makeStatistics() -> WishStatistics {
        var stats = WishStatistics()
        for wish in allWishes {
            stats.total += 1
            stats.kindCounts[wish.kind, default: 0] += 1
            switch wish.status {
            case "fulfilled":
                stats.fulfilledCount += 1
                stats.fulfilledSpentCents += (wish.actualCost > 0 ? wish.actualCost : wish.budget)
            case "relinquished":
                stats.relinquishedCount += 1
                stats.relinquishedSavedCents += wish.budget
            default:
                stats.wantingCount += 1
                stats.wantingBudgetCents += wish.budget
            }
        }
        return stats
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
        // 一次性绑定统计与筛选结果，避免 body 内重复全量扫描
        let stats = makeStatistics()
        let wishes = filteredWishes

        ScrollView {
            // LazyVStack 作为 ScrollView 直接子视图，长列表才具备懒加载能力
            LazyVStack(alignment: .leading, spacing: ArchiveSpacing.xl) {
                headerSection

                statisticsCardsSection(stats: stats)

                filterPillsSection(stats: stats)

                if let err = errorMessage {
                    Text(err)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                if appState.isLoading {
                    // 加载中：与「真的为空」区分，避免用户误以为心愿被清空
                    ProgressView("正在誊写心愿清单…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if wishes.isEmpty {
                    emptyPlaceholder
                } else {
                    wishesGridSection(wishes)
                }
            }
            .padding(ArchiveSpacing.xl)
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
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: ArchiveSpacing.s) {
                    Text("心愿清单")
                        .font(ArchiveTypography.editorialSerif(size: 24, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("好物 · 旅程 · 里程碑")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
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
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }

            Text("生活的三维期冀：花钱可得的称手好物、需要闲暇与决心的山川行旅、心智进阶的人生里程碑。无截止死线，真实倒映生活向往。")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .lineSpacing(3)
        }
    }

    // MARK: - 2. 统计大盘三列纸卡
    private func statisticsCardsSection(stats: WishStatistics) -> some View {
        HStack(spacing: ArchiveCardMetrics.padding) {
            statCard(
                title: "在愿向往 (进行中)",
                count: "\(stats.wantingCount) 项",
                subText: stats.wantingBudgetCents > 0 ? "预算 ¥\(FormatUtils.formattedYuan(cents: stats.wantingBudgetCents, includeSymbol: false))" : nil,
                accentColor: ArchivePalette.inkPrimary
            )

            statCard(
                title: "圆满达成 (已归册)",
                count: "\(stats.fulfilledCount) 项",
                subText: stats.fulfilledSpentCents > 0 ? "投入 ¥\(FormatUtils.formattedYuan(cents: stats.fulfilledSpentCents, includeSymbol: false))" : nil,
                accentColor: ArchivePalette.accentMoss
            )

            statCard(
                title: "理性拔草 (已释怀)",
                count: "\(stats.relinquishedCount) 项",
                subText: stats.relinquishedSavedCents > 0 ? "省下 ¥\(FormatUtils.formattedYuan(cents: stats.relinquishedSavedCents, includeSymbol: false))" : nil,
                accentColor: ArchivePalette.accentWarm
            )
        }
    }

    private func statCard(title: String, count: String, subText: String?, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
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
        .padding(ArchiveCardMetrics.padding)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
    }

    // MARK: - 3. 双级筛选胶囊
    private func filterPillsSection(stats: WishStatistics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 维度 Tab
            HStack(spacing: 6) {
                PaperPillButton(title: "全维度 (\(stats.total))", isSelected: selectedKind == "all") {
                    guard selectedKind != "all" else { return }
                    selectedKind = "all"
                }
                PaperPillButton(title: "好物器物 (\(stats.kindCounts["item"] ?? 0))", isSelected: selectedKind == "item") {
                    guard selectedKind != "item" else { return }
                    selectedKind = "item"
                }
                PaperPillButton(title: "行旅探索 (\(stats.kindCounts["travel"] ?? 0))", isSelected: selectedKind == "travel") {
                    guard selectedKind != "travel" else { return }
                    selectedKind = "travel"
                }
                PaperPillButton(title: "阶段进阶 (\(stats.kindCounts["milestone"] ?? 0))", isSelected: selectedKind == "milestone") {
                    guard selectedKind != "milestone" else { return }
                    selectedKind = "milestone"
                }
            }

            // 状态 Tab
            HStack(spacing: 6) {
                PaperPillButton(title: "向往中 (\(stats.wantingCount))", isSelected: selectedStatus == "wanting") {
                    guard selectedStatus != "wanting" else { return }
                    selectedStatus = "wanting"
                }
                PaperPillButton(title: "已圆满 (\(stats.fulfilledCount))", isSelected: selectedStatus == "fulfilled") {
                    guard selectedStatus != "fulfilled" else { return }
                    selectedStatus = "fulfilled"
                }
                PaperPillButton(title: "已拔草 (\(stats.relinquishedCount))", isSelected: selectedStatus == "relinquished") {
                    guard selectedStatus != "relinquished" else { return }
                    selectedStatus = "relinquished"
                }
                PaperPillButton(title: "全部 (\(stats.total))", isSelected: selectedStatus == "all") {
                    guard selectedStatus != "all" else { return }
                    selectedStatus = "all"
                }
            }
        }
    }

    // MARK: - 4. 网格卡片
    private func wishesGridSection(_ wishes: [Wish]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: ArchiveCardMetrics.padding), GridItem(.flexible(), spacing: ArchiveCardMetrics.padding)], spacing: ArchiveCardMetrics.padding) {
            ForEach(wishes) { wish in
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
        ArchiveEmptyState(
            systemName: ArchiveIcon.wishes.systemName,
            title: "该筛选维度下尚无心愿条目",
            message: "记下一件心仪器物、一处远方山川或一项阶段进阶目标。",
            primaryTitle: "许下心愿",
            primaryAction: { showNewWishSheet = true }
        )
        .frame(minHeight: 180)
    }

    private func deleteWish(_ wish: Wish) {
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteWish(id: wish.id)
                // 心愿的伴生散页要一并从时间流移除
                await appState.refreshAfterSecondaryWrite()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 预览 (Preview)

#Preview("心愿清单") {
    WishlistView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}
