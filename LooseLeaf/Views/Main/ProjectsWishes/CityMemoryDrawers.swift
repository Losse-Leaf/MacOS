import SwiftUI

/// 城市 / 省份回忆抽屉弹窗集合 (CityMemoryDrawerSheet / ProvinceMemoryDrawerSheet)
/// 从 ProjectsWishesView 中拆出的独立 Sheet 组件：
/// 1. CityMemoryDrawerSheet —— 属地散页、相纸与开销的城市回忆抽屉
/// 2. ProvinceMemoryDrawerSheet —— 全省行迹票根与属地手记的山河回忆抽屉
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

// MARK: - 城市回忆抽屉弹窗 (CityMemoryDrawerSheet)

@MainActor
public struct CityMemoryDrawerSheet: View {
    let cityCode: String
    let cityName: String
    var onDismiss: () -> Void

    @State private var drawer: CityMemoryDrawerResponse?
    @State private var isLoading: Bool = true
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(cityName) · 城市回忆抽屉")
                        .font(ArchiveTypography.editorialSerif(size: 18, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("行政代码 \(cityCode)")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                Button("关闭") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            if isLoading {
                ProgressView("正在翻找属地散页与相纸…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.accentWarm)
            } else if let d = drawer {
                ScrollView {
                    VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                Text("到访次数")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text("\(d.visitStats.totalVisits) 次")
                                    .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                            }
                            if !d.visitStats.firstVisitedAt.isEmpty {
                                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                    Text("首访日期")
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(d.visitStats.firstVisitedAt)
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                }
                            }
                            if d.ledgerSummary.totalSpent > 0 {
                                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                    Text("属地开销")
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(FormatUtils.formattedYuan(cents: d.ledgerSummary.totalSpent, includeSymbol: true))
                                        .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                }
                            }
                        }

                        if !d.entries.isEmpty {
                            Text("属地散页随笔 (\(d.entries.count))")
                                .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            ForEach(d.entries) { entry in
                                VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                                    HStack {
                                        Text(entry.title.isEmpty ? "散页手记" : entry.title)
                                            .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        Spacer()
                                        Text(entry.parsedDate.dotDate)
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                    }
                                    Text(entry.content)
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .lineLimit(3)
                                }
                                .padding(10)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            } else {
                // 兜底分支：抽屉为空且无错误时给出明确说明，避免内容区整片空白
                ArchiveEmptyState(
                    systemName: ArchiveIcon.detail.systemName,
                    title: "暂无该城市的回忆抽屉",
                    message: "这座城市尚未沉淀公开或私密散页，可在时间流中补记一段漫游手记。"
                )
                .frame(minHeight: 200)
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
            do {
                drawer = try await APIClient.shared.fetchCityMemoryDrawer(cityCode: cityCode)
                isLoading = false
            } catch {
                errorText = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - 省级山河回忆抽屉弹窗 (ProvinceMemoryDrawerSheet)

@MainActor
public struct ProvinceMemoryDrawerSheet: View {
    let adcode: String
    let provinceName: String
    var onDismiss: () -> Void

    @State private var drawer: ProvinceMemoryDrawerResponse?
    @State private var isLoading: Bool = true
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(provinceName) · 省级山河回忆抽屉")
                        .font(ArchiveTypography.editorialSerif(size: 18, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("行政代码前缀 \(adcode)")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                Button("关闭") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            if isLoading {
                ProgressView("正在聚合全省行迹票根与属地手记…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.accentWarm)
            } else if let d = drawer {
                ScrollView {
                    VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                Text("点亮城邑")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text("\(d.visitedCities.count) 座城")
                                    .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                            }
                            VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                Text("总履迹篇幅")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text("\(d.footprints.count) 次")
                                    .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                            }
                            if d.ledgerSummary.totalSpent > 0 {
                                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                    Text("省内花销")
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(FormatUtils.formattedYuan(cents: d.ledgerSummary.totalSpent, includeSymbol: true))
                                        .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                }
                            }
                        }
                        .padding(ArchiveSpacing.m)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))

                        if !d.visitedCities.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("到访城市分布")
                                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                HStack(spacing: 6) {
                                    ForEach(d.visitedCities) { city in
                                        Text("\(city.cityName) (\(city.visitCount))")
                                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                            .padding(.horizontal, ArchiveSpacing.s)
                                            .padding(.vertical, ArchiveSpacing.xs)
                                            .background(ArchivePalette.archiveSubtle)
                                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                    }
                                }
                            }
                        }

                        if !d.entries.isEmpty {
                            VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                                Text("属地散页手记 (\(d.entries.count))")
                                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)

                                ForEach(d.entries) { entry in
                                    VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                                        HStack {
                                            Text(entry.title.isEmpty ? "散页随笔" : entry.title)
                                                .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                                                .foregroundStyle(ArchivePalette.inkPrimary)
                                            Spacer()
                                            Text(entry.parsedDate.dotDate)
                                                .font(ArchiveTypography.monoScale(size: 10.5))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                        }
                                        Text(entry.content)
                                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                            .lineLimit(3)
                                    }
                                    .padding(10)
                                    .background(ArchivePalette.archiveSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            } else {
                // 兜底分支：抽屉为空且无错误时给出明确说明，避免内容区整片空白
                ArchiveEmptyState(
                    systemName: ArchiveIcon.detail.systemName,
                    title: "暂无该省份的山河回忆抽屉",
                    message: "这片山河尚未沉淀行迹票根与属地手记，可在山川印谱中继续点亮城市。"
                )
                .frame(minHeight: 200)
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
            do {
                drawer = try await APIClient.shared.fetchProvinceMemoryDrawer(adcode: adcode)
                isLoading = false
            } catch {
                errorText = error.localizedDescription
                isLoading = false
            }
        }
    }
}
