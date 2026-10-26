// PaperHeatmap.swift
// 时光刻度组件 (Temporal Gap Separator & Life Activity Heatmap)
// 职责：归档时间轴上的「岁月留白」刻度切线与 GitHub 风格 52 周生活刻度热力图，
//       属于时间维度的可视化呈现，不涉及表单控件与通用按钮样式。
// 来源：由 Views/Components/PaperComponents.swift 按职责拆分而来，代码逻辑保持原样。

import SwiftUI

/// 岁月留白刻度切线 (Temporal Gap Separator)
/// 遵循 docs/ecosystem.md §4.1.3：当相邻记录跨度 >= 14 天时自动插入留白标注
/// 融合树状时间轴树干母线与年轮休眠节点 (Tree Ring Dormant Node)
public struct TemporalGapDivider: View {
    public let days: Int

    public init(days: Int) {
        self.days = days
    }

    public var body: some View {
        HStack(spacing: 0) {
            // 左侧树干贯穿与年轮留白节
            ZStack {
                Rectangle()
                    .fill(ArchivePalette.borderSubtle.opacity(0.7))
                    .frame(width: 1.5)
                    .padding(.leading, 6)

                ZStack {
                    Circle()
                        .fill(ArchivePalette.archivePaper)
                        .frame(width: 13, height: 13)
                    Circle()
                        .stroke(ArchivePalette.inkMuted.opacity(0.6), lineWidth: 1.2)
                        .frame(width: 13, height: 13)
                    Circle()
                        .stroke(ArchivePalette.inkMuted.opacity(0.3), lineWidth: 0.8)
                        .frame(width: 8, height: 8)
                }
                .padding(.leading, 6)
            }
            .frame(width: 27)
            .padding(.trailing, 6)

            HStack(spacing: ArchiveSpacing.m) {
                Rectangle()
                    .fill(ArchivePalette.borderDivider)
                    .frame(height: 0.5)
                Text("—— 年轮留白 · 历经 \(days) 天的沉默与沉淀 ——")
                    .font(ArchiveTypography.editorialSerif(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .fixedSize()
                Rectangle()
                    .fill(ArchivePalette.borderDivider)
                    .frame(height: 0.5)
            }
        }
        .padding(.vertical, 8)
    }
}

/// GitHub 风格 52 周生活刻度热力图 (LifeActivityMap)
/// 严格锚定北京时间今天 (Today)，回溯 26~52 周，展现散页书写密度
/// 网格日期预计算，消除 body 渲染内 266 次 Calendar.date(byAdding:) 冗余计算
public struct LifeActivityHeatmapView: View {
    public let entryCounts: [String: Int]
    public let totalCount: Int
    public var weeksCount: Int
    @Binding public var selectedDate: String?

    private struct DayCell: Identifiable {
        let id: String
        let dateKey: String
        let isToday: Bool
    }

    /// 静态日历刻度：52 周 × 7 天 = 364 格
    /// 刻度仅在首次访问时构建一次，之后所有视图共享同一份不可变数据，
    /// 彻底消除「每次 init 都调用 364 次 Calendar.date(byAdding:)」的开销。
    /// 注：刻度以「首次访问当天」为锚点，跨零点不会自动重算（对热力图统计无实质影响）。
    private enum HeatmapCalendar {
        /// 固定 52 周刻度：自最早一周到本周，与周数组下标一一对应
        static let weeks: [[DayCell]] = {
            let cal = FormatUtils.beijingCalendar
            let today = cal.startOfDay(for: Date())
            let todayKey = FormatUtils.beijingDateString(from: today)

            var result: [[DayCell]] = []
            for weekOffset in (0..<52).reversed() {
                var days: [DayCell] = []
                for dayOffset in 0..<7 {
                    let totalDaysAgo = weekOffset * 7 + (6 - dayOffset)
                    let cellDate = cal.date(byAdding: .day, value: -totalDaysAgo, to: today) ?? today
                    let key = FormatUtils.beijingDateString(from: cellDate)
                    days.append(DayCell(id: "\(weekOffset)-\(dayOffset)-\(key)", dateKey: key, isToday: key == todayKey))
                }
                result.append(days)
            }
            return result
        }()
    }

    private let precomputedWeeks: [[DayCell]]

    public init(
        entryCounts: [String: Int],
        totalCount: Int,
        weeksCount: Int = 52,
        selectedDate: Binding<String?> = .constant(nil)
    ) {
        self.entryCounts = entryCounts
        self.totalCount = totalCount
        self.weeksCount = weeksCount
        self._selectedDate = selectedDate

        // O(1) 取用静态刻度：weeksCount 决定截取最近若干周（缓存末位为本周）
        self.precomputedWeeks = Array(HeatmapCalendar.weeks.suffix(max(1, weeksCount)))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: ArchiveSpacing.s) {
                Image(systemName: "chart.dots.scatter")
                    .font(.system(size: 11))
                    .foregroundStyle(ArchivePalette.accentMoss)
                Text("时光生活刻度")
                    .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Text("·")
                    .foregroundStyle(ArchivePalette.inkMuted)
                Text("共 \(totalCount) 篇散页手稿留痕")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                // 1. 月份标尺（索引即周序号，刻度静态缓存后保持稳定）
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 28) // 留给左侧星期标尺的对齐空间
                    ForEach(Array(stride(from: 0, to: precomputedWeeks.count, by: 8)), id: \.self) { idx in
                        if let firstDay = precomputedWeeks[idx].first {
                            let parts = firstDay.dateKey.split(separator: "-")
                            if parts.count >= 2, let m = Int(parts[1]) {
                                Text("\(m)月")
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, ArchiveSpacing.xs)

                // 2. 星期标尺与 52 周热力图矩阵
                HStack(alignment: .top, spacing: 6) {
                    VStack(spacing: 6) {
                        Text("周一")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .frame(height: 12)
                        Text("周四")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .frame(height: 12)
                        Text("周日")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .frame(height: 12)
                    }
                    .padding(.top, ArchiveSpacing.xxs)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 3) {
                            // 下标即周序号：静态刻度下顺序恒定，索引 ID 稳定
                            ForEach(precomputedWeeks.indices, id: \.self) { weekIdx in
                                VStack(spacing: 3) {
                                    ForEach(precomputedWeeks[weekIdx]) { cell in
                                        let count = entryCounts[cell.dateKey, default: 0]
                                        let isSelected = selectedDate == cell.dateKey
                                        let style = cellStyle(for: count)
                                        Button {
                                            if selectedDate == cell.dateKey {
                                                selectedDate = nil
                                            } else {
                                                selectedDate = cell.dateKey
                                            }
                                        } label: {
                                            RoundedRectangle(cornerRadius: 1.5)
                                                .fill(style.fill)
                                                .frame(width: 9, height: 9)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 1.5)
                                                        .stroke(
                                                            isSelected
                                                                ? ArchivePalette.accentWarm
                                                                : (cell.isToday ? ArchivePalette.accentWarm.opacity(0.7) : style.stroke),
                                                            lineWidth: isSelected ? 1.5 : style.lineWidth
                                                        )
                                                )
                                                // 视觉仍是 9×9，命中区扩到 14×14 便于指针点选
                                                .contentShape(Rectangle().size(width: 14, height: 14))
                                                .help("\(cell.dateKey.replacingOccurrences(of: "-", with: ".")) · \(count) 篇手稿留痕")
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(cell.dateKey)，\(count) 篇手稿留痕")
                                        .accessibilityValue(count > 0 ? "有记录" : "无记录")
                                    }
                                }
                            }
                        }
                    }
                }

                // 3. 底部纸墨色阶图例（与实际格色阶共用同一规格）
                HStack(spacing: 6) {
                    Spacer()
                    Text("岁月留白")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    ForEach(0...4, id: \.self) { lvl in
                        let style = cellStyle(for: lvl)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(style.fill)
                            .frame(width: 8, height: 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.5)
                                    .stroke(style.stroke, lineWidth: style.lineWidth)
                            )
                    }

                    Text("笔墨丰盛")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .padding(.top, ArchiveSpacing.xs)
            }
            .padding(.top, ArchiveSpacing.xxs)
        }
        .padding(ArchiveSpacing.m)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
        .paperElevation(1)
    }

    /// 单格的填充与描边规格
    private struct CellStyle {
        let fill: Color
        let stroke: Color
        let lineWidth: CGFloat
    }

    /// 热力图色阶：
    /// - 0 篇使用可见的浅灰描边（此前用近不可见的 borderSubtle，空白格形同消失）
    /// - 三档以上拉开透明度差异，色阶更易分辨
    private func cellStyle(for count: Int) -> CellStyle {
        switch count {
        case 0:
            return CellStyle(
                fill: ArchivePalette.inkMuted.opacity(0.08),
                stroke: ArchivePalette.inkMuted.opacity(0.18),
                lineWidth: 0.5
            )
        case 1:
            return CellStyle(fill: ArchivePalette.accentMoss.opacity(0.36), stroke: .clear, lineWidth: 0)
        case 2:
            return CellStyle(fill: ArchivePalette.accentMoss.opacity(0.60), stroke: .clear, lineWidth: 0)
        case 3:
            return CellStyle(fill: ArchivePalette.accentMoss.opacity(0.84), stroke: .clear, lineWidth: 0)
        default:
            return CellStyle(fill: ArchivePalette.accentMoss, stroke: .clear, lineWidth: 0)
        }
    }
}
