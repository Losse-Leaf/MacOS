import SwiftUI

/// 年度生活年鉴五幕画卷弹窗 (AnnualAlmanacSheet)
/// 从 ProjectsWishesView 中拆出的独立 Sheet 组件：
/// 汇聚岁月卷首 / 山川行迹 / 心愿圆满 / 四季浮光 / 柴米油盐五幕年度画卷。
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

// MARK: - 年度生活年鉴五幕画卷弹窗 (AnnualAlmanacSheet)

@MainActor
public struct AnnualAlmanacSheet: View {
    var onDismiss: () -> Void

    @State private var selectedYear: Int = FormatUtils.beijingCurrentYearMonth().year
    @State private var almanac: AnnualAlmanacResponse?
    @State private var isLoading: Bool = true
    @State private var errorText: String?

    private var availableYears: [Int] {
        let currentYear = FormatUtils.beijingCurrentYearMonth().year
        let entryYears = AppState.shared.entries.compactMap { entry -> Int? in
            guard entry.occurredAt.count >= 4 else { return nil }
            return Int(entry.occurredAt.prefix(4))
        }
        let earliest = min(entryYears.min() ?? currentYear, currentYear)
        return Array((earliest...currentYear).reversed())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            HStack {
                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                    Text("《散页 · \(selectedYear) 年度生活年鉴》")
                        .font(ArchiveTypography.editorialSerif(size: 18, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("岁月卷首 · 山川行迹 · 心愿圆满 · 浮光掠影 · 柴米油盐")
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(availableYears, id: \.self) { yr in
                        PaperPillButton(title: "\(yr) 年", isSelected: selectedYear == yr) {
                            selectedYear = yr
                            Task { await loadAlmanac() }
                        }
                    }
                    Button("关闭") { onDismiss() }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .paperButtonFocusRing()
                }
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            if isLoading {
                ProgressView("正在装订年度年鉴画卷…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.accentWarm)
            } else if let a = almanac {
                ScrollView {
                    VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
                        // 第一幕：岁月卷首
                        HStack(spacing: 20) {
                            almanacStat("散页篇幅", "\(a.prologue.totalEntries) 篇")
                            almanacStat("点亮城市", "\(a.prologue.citiesVisited) 城")
                            almanacStat("圆满心愿", "\(a.prologue.wishesFulfilled) 愿")
                            almanacStat("记账笔数", "\(a.prologue.txCount) 笔")
                        }
                        .padding(ArchiveSpacing.m)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))

                        // 第二幕：山川行迹
                        if !a.atlas.cities.isEmpty {
                            Text("第二幕 · 山川行迹 (\(a.atlas.totalCities) 城)")
                                .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                            Text(a.atlas.cities.map(\.cityName).joined(separator: " · "))
                                .font(ArchiveTypography.bodySans(size: 12.5))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                        }

                        // 第三幕：心愿圆满
                        Text("第三幕 · 心愿圆满 (已达成 \(a.wishes.fulfilledCount) / 在愿 \(a.wishes.wantingCount))")
                            .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))

                        // 第四幕：浮光掠影 · 四季流转
                        VStack(alignment: .leading, spacing: 6) {
                            Text("第四幕 · 浮光掠影 · 四季流转")
                                .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: ArchiveSpacing.s) {
                                seasonCard(title: "春生 · 春季篇", entry: a.highlights.spring, tint: ArchivePalette.accentMoss)
                                seasonCard(title: "夏长 · 夏季篇", entry: a.highlights.summer, tint: ArchivePalette.accentWarm)
                                seasonCard(title: "秋收 · 秋季篇", entry: a.highlights.autumn, tint: Color(red: 0.83, green: 0.53, blue: 0.02))
                                seasonCard(title: "冬藏 · 冬季篇", entry: a.highlights.winter, tint: ArchivePalette.inkSecondary)
                            }
                        }

                        // 第五幕：柴米油盐
                        if a.finances.totalExpense > 0 || a.finances.totalIncome > 0 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("第五幕 · 柴米油盐")
                                    .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                                HStack(spacing: 18) {
                                    Text("总支出 \(FormatUtils.formattedYuan(cents: a.finances.totalExpense, includeSymbol: true))")
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                    Text("总收入 \(FormatUtils.formattedYuan(cents: a.finances.totalIncome, includeSymbol: true))")
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                    Text(String(format: "取悦自己占比 %.1f%%", a.finances.wishSpendingRatio))
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
        .padding(22)
        .frame(
            minWidth: ArchiveSheetWidth.wide,
            idealWidth: ArchiveSheetWidth.wide,
            maxWidth: ArchiveSheetWidth.wide
        )
        .background(ArchivePalette.archivePaper)
        .task {
            await loadAlmanac()
        }
    }

    private func seasonCard(title: String, entry: LifeEntry?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                .foregroundStyle(tint)
            if let entry {
                Text(entry.title.isEmpty ? "无题随笔" : entry.title)
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.body, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .lineLimit(1)
                if !entry.content.isEmpty {
                    Text(entry.content)
                        .font(ArchiveTypography.bodySans(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .lineLimit(2)
                }
            } else {
                Text("暂无季候留痕")
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
        }
        .padding(ArchiveSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
    }

    private func almanacStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
            Text(label)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(ArchivePalette.inkMuted)
            Text(value)
                .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
        }
    }

    private func loadAlmanac() async {
        isLoading = true
        errorText = nil
        do {
            almanac = try await APIClient.shared.fetchAnnualAlmanac(year: selectedYear)
            isLoading = false
        } catch {
            errorText = error.localizedDescription
            isLoading = false
        }
    }
}
