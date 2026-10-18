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

    public init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 14))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Text("生活刻度统计")
                        .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 核心指标网格
            VStack(spacing: 20) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
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
                    .font(ArchiveTypography.editorialSerif(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(22)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 底栏关闭按钮
            HStack {
                if isLoading {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.6)
                        Text("核对中枢中…")
                            .font(ArchiveTypography.monoScale(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
                Spacer()
                Button("关闭") {
                    onDismiss()
                }
                .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                .foregroundStyle(ArchivePalette.archivePaper)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(ArchivePalette.inkPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(ArchivePalette.archiveSubtle.opacity(0.4))
        }
        .frame(width: 440)
        .background(ArchivePalette.archivePaper)
        .task {
            isLoading = true
            defer { isLoading = false }
            if let fetched = try? await APIClient.shared.fetchGlobalStats() {
                self.stats = fetched
            }
        }
    }

    private func metricCard(title: String, value: String, unit: String?, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ArchiveTypography.monoScale(size: 11))
                .foregroundStyle(ArchivePalette.inkMuted)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(ArchiveTypography.editorialSerif(size: 26, weight: .semibold))
                    .foregroundStyle(accentColor)

                if let unit {
                    Text(unit)
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ArchivePalette.archiveSubtle.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }
}
