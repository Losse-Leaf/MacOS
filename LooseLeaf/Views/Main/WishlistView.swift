import SwiftUI

/// 心愿清单独立主视图 (WishlistView)
/// 1. 标头：“心愿清单 · 好物 · 旅程 · 里程碑” + “许下心愿”快捷入口
/// 2. 顶部三列大盘指标卡：在愿向往（预算 ¥）、圆满达成（投入 ¥）、理性拔草（省下 ¥）
/// 3. 双级过滤胶囊：维度（全维度/好物/旅程/里程碑）与状态（向往中/圆满达成/理性拔草/全部）
/// 4. 心愿网格卡片与圆满达成归册仪式 (ResolveWishSheet)，支持 ⌘K 定位与 ⌘Z 撤销删除
@MainActor
public struct WishlistView: View {
    @Bindable var appState: AppState

    @State private var selectedKind: String = "all"
    @State private var selectedStatus: String = "wanting"

    @State private var showNewWishSheet: Bool = false
    @State private var editingWish: Wish?
    @State private var resolvingWish: Wish?
    @State private var errorMessage: String?
    @State private var highlightedId: Int?

    public init(appState: AppState) {
        self.appState = appState
    }

    private var allWishes: [Wish] { appState.wishes }

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

    private func isWantingStatus(_ s: String) -> Bool {
        s == "wanting" || s.isEmpty || s == "pending" || s == "shelved"
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

    private var filteredWishes: [Wish] {
        allWishes.filter { wish in
            let matchKind = (selectedKind == "all") || (wish.kind == selectedKind)
            let matchStatus: Bool
            if selectedStatus == "all" {
                matchStatus = true
            } else if selectedStatus == "wanting" {
                matchStatus = isWantingStatus(wish.status)
            } else {
                matchStatus = (wish.status == selectedStatus)
            }
            return matchKind && matchStatus
        }
    }

    public var body: some View {
        let stats = makeStatistics()
        let wishes = filteredWishes

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ArchiveSpacing.xl) {
                    headerSection

                    statisticsCardsSection(stats: stats)

                    filterPillsSection(stats: stats)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .lineLimit(2)
                    }

                    if appState.isLoading && allWishes.isEmpty {
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
            .onAppear {
                consumeHighlightedWishIfNeeded(proxy: proxy)
            }
            .onChange(of: appState.navigation.highlightedWishId) { _, _ in
                consumeHighlightedWishIfNeeded(proxy: proxy)
            }
        }
        .sheet(isPresented: $showNewWishSheet) {
            WishEditorSheet(appState: appState) {
                showNewWishSheet = false
            }
        }
        .sheet(item: $editingWish) { wish in
            WishEditorSheet(appState: appState, wish: wish) {
                editingWish = nil
            }
        }
        .sheet(item: $resolvingWish) { wish in
            ResolveWishSheet(appState: appState, wish: wish) {
                resolvingWish = nil
            }
        }
    }

    private func consumeHighlightedWishIfNeeded(proxy: ScrollViewProxy) {
        guard let targetId = appState.navigation.highlightedWishId else { return }
        selectedKind = "all"
        selectedStatus = "all"
        highlightedId = targetId
        appState.navigation.highlightedWishId = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(ArchiveMotion.standard) {
                proxy.scrollTo(targetId, anchor: .center)
            }
            try? await Task.sleep(for: .seconds(2.4))
            if highlightedId == targetId {
                highlightedId = nil
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
                .paperButtonFocusRing()
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
                    .foregroundStyle(count.hasPrefix("0") ? ArchivePalette.inkMuted : accentColor)
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
            ScrollView(.horizontal, showsIndicators: false) {
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
            }
            .horizontalFadeMask()

            ScrollView(.horizontal, showsIndicators: false) {
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
            .horizontalFadeMask()
        }
    }

    // MARK: - 4. 网格卡片
    private func wishesGridSection(_ wishes: [Wish]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: ArchiveCardMetrics.padding), GridItem(.flexible(), spacing: ArchiveCardMetrics.padding)], spacing: ArchiveCardMetrics.padding) {
            ForEach(wishes) { wish in
                WishCardView(
                    wish: wish,
                    isHighlighted: highlightedId == wish.id,
                    onResolve: {
                        resolvingWish = wish
                    },
                    onEdit: {
                        editingWish = wish
                    },
                    onDelete: {
                        appState.askConfirm(
                            title: "确认删除该心愿？",
                            message: "删除后该心愿及伴生散页将移除，可在短时间内通过 ⌘Z 撤销。",
                            confirmText: "删除心愿",
                            danger: true
                        ) {
                            deleteWish(wish)
                        }
                    }
                )
                .id(wish.id)
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
        errorMessage = nil
        Task { @MainActor in
            do {
                try await appState.deleteWishAction(wish)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if DEBUG
#Preview("心愿清单") {
    WishlistView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}
#endif
