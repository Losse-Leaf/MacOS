import SwiftUI

/// 生活刻度统计模态框 (StatsModalView)
/// 严格 1:1 对标 Web 端 `web/src/components/StatsModal.vue`
/// 呈现生活印记、相纸照片、造物项目与本月实际支出指标
@MainActor
public struct StatsModalView: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var stats: GlobalStats? = nil
    @State private var isLoading: Bool = true
    /// 焦点环状态：模态获得键盘焦点时显示高亮描边
    @FocusState private var isModalFocused: Bool

    public init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack {
                HStack(spacing: ArchiveSpacing.s) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 14))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .accessibilityHidden(true)
                    Text("生活刻度统计")
                        .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                Spacer()

                // 关闭按钮：命中区 ≥ 28pt 且带无障碍标签
                PaperIconButton(
                    systemName: "xmark",
                    label: "关闭统计弹窗",
                    help: "关闭统计弹窗",
                    size: 12,
                    tint: ArchivePalette.inkMuted
                ) {
                    onDismiss()
                }
            }
            .padding(.horizontal, ArchiveSpacing.xl)
            .padding(.vertical, ArchiveSpacing.l)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 核心指标网格 / 空态
            contentArea

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 底栏关闭按钮
            HStack {
                if isLoading {
                    HStack(spacing: ArchiveSpacing.xs) {
                        ProgressView().scaleEffect(0.6)
                        Text("核对中枢中…")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
                Spacer()
                Button("关闭") {
                    onDismiss()
                }
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                .foregroundStyle(ArchivePalette.archivePaper)
                .padding(.horizontal, ArchiveSpacing.l)
                .padding(.vertical, ArchiveSpacing.s)
                .background(ArchivePalette.inkPrimary)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, ArchiveSpacing.xl)
            .padding(.vertical, ArchiveSpacing.m)
            .background(ArchivePalette.archiveSubtle.opacity(0.4))
        }
        // 宽度改为弹性区间，避免固定宽度在不同动态字体下截断内容
        .frame(
            minWidth: ArchiveSheetWidth.compact,
            idealWidth: ArchiveSheetWidth.standard,
            maxWidth: ArchiveSheetWidth.standard
        )
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.lg))
        // 焦点环：获得键盘焦点时高亮外框
        .focusable()
        .focused($isModalFocused)
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.lg)
                .stroke(isModalFocused ? ArchivePalette.accentWarm : Color.clear, lineWidth: 2)
        )
        // ESC 关闭（覆盖到整个模态区域）
        .onExitCommand {
            onDismiss()
        }
        .task {
            isLoading = true
            defer { isLoading = false }
            if let fetched = try? await APIClient.shared.fetchGlobalStats() {
                self.stats = fetched
            }
        }
    }

    // MARK: - 内容区

    /// 内容区：加载中 / 空态 / 指标网格
    @ViewBuilder
    private var contentArea: some View {
        if isLoading && !hasAnyData {
            VStack(spacing: ArchiveSpacing.m) {
                ProgressView()
                    .controlSize(.regular)
                Text("正在核对中枢中的生活刻度…")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(ArchiveSpacing.xl)
        } else if !hasAnyData {
            // 空数据：统一空状态组件
            ArchiveEmptyState(
                systemName: "chart.bar",
                title: "暂无生活刻度",
                message: "中枢尚未记录任何散页、相片或造物项目。录入第一篇散页后，这里就会浮现属于你的时间刻度。"
            )
            .padding(ArchiveSpacing.l)
        } else {
            VStack(spacing: ArchiveSpacing.xl) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: ArchiveSpacing.m), GridItem(.flexible(), spacing: ArchiveSpacing.m)], spacing: ArchiveSpacing.m) {
                    metricCard(
                        title: "生活印记总数",
                        value: "\(stats?.totalEntries ?? appState.entries.count)",
                        unit: "篇",
                        accentColor: ArchivePalette.inkPrimary
                    )

                    metricCard(
                        title: "胶卷与相片",
                        value: "\(stats?.totalPhotos ?? appState.entries.reduce(0) { $0 + $1.attachments.count })",
                        unit: "张",
                        accentColor: ArchivePalette.inkPrimary
                    )

                    metricCard(
                        title: "造物与项目",
                        value: "\(stats?.totalProjects ?? appState.projects.count)",
                        unit: "件",
                        accentColor: ArchivePalette.inkPrimary
                    )

                    metricCard(
                        title: "本月实际支出",
                        value: FormatUtils.formattedYuan(cents: stats?.monthExpense ?? appState.transactionSummary.totalExpense, includeSymbol: true),
                        unit: nil,
                        accentColor: ArchivePalette.accentWarm
                    )
                }

                Text("每一个数字，都是真实流淌度过的时间。")
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, ArchiveSpacing.xs)
            }
            .padding(ArchiveSpacing.xl)
        }
    }

    /// 是否存在任何可用于统计的数据
    private var hasAnyData: Bool {
        let totalEntries = stats?.totalEntries ?? appState.entries.count
        let totalPhotos = stats?.totalPhotos ?? appState.entries.reduce(0) { $0 + $1.attachments.count }
        let totalProjects = stats?.totalProjects ?? appState.projects.count
        let monthExpense = stats?.monthExpense ?? appState.transactionSummary.totalExpense
        return totalEntries > 0 || totalPhotos > 0 || totalProjects > 0 || monthExpense > 0
    }

    private func metricCard(title: String, value: String, unit: String?, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            Text(title)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(ArchivePalette.inkMuted)

            HStack(alignment: .firstTextBaseline, spacing: ArchiveSpacing.xs) {
                Text(value)
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.display, weight: .semibold))
                    .foregroundStyle(accentColor)

                if let unit {
                    Text(unit)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ArchiveCardMetrics.padding)
        .background(ArchivePalette.archiveSubtle.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: ArchiveCardMetrics.radius))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveCardMetrics.radius)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)\(unit ?? "")")
    }
}
