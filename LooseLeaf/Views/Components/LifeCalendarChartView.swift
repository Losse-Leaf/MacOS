// LifeCalendarChartView.swift
// 生活刻度 · 时光日历图 (Life Calendar Chart)
// 职责：取代原 GitHub 风格纯色块热力图，以真实公历月历/年历与 ECharts 架构交互呈现生活散页沉淀。
// 遵循 diagram-design 技能 Editorial 纸墨色盘与 WCAG AA 对比度规范。

import SwiftUI
import AppKit

/// 日历呈现形态
public enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case monthGrid = "月历视界"
    case annualMatrix = "年度全景"
    case echarts = "ECharts 画卷"

    public var id: String { rawValue }
}

/// 生活刻度 · 时光日历图视图
public struct LifeCalendarChartView: View {
    public let entryCounts: [String: Int]
    public let totalCount: Int
    @Binding public var selectedDate: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var displayMode: CalendarDisplayMode = .monthGrid
    @State private var currentYear: Int
    @State private var currentMonth: Int

    public init(
        entryCounts: [String: Int],
        totalCount: Int,
        selectedDate: Binding<String?> = .constant(nil)
    ) {
        self.entryCounts = entryCounts
        self.totalCount = totalCount
        self._selectedDate = selectedDate

        let now = FormatUtils.beijingCurrentYearMonth()
        _currentYear = State(initialValue: now.year)
        _currentMonth = State(initialValue: now.month)
    }

    private var isCurrentMonthActive: Bool {
        let now = FormatUtils.beijingCurrentYearMonth()
        return currentYear == now.year && currentMonth == now.month
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            // 顶栏：标题、模式切换器与手稿统计
            headerToolbar

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 主画布：按模式切换呈现
            Group {
                switch displayMode {
                case .monthGrid:
                    monthCalendarView
                case .annualMatrix:
                    annualMatrixView
                case .echarts:
                    echartsInteractiveView
                }
            }

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))

            // 底栏：纸墨色阶图例与月度统计小记
            footerLegendBar
        }
        .padding(ArchiveSpacing.m)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
        .paperElevation(1)
    }

    // MARK: - 顶栏与模式切换

    private var headerToolbar: some View {
        HStack(alignment: .center, spacing: ArchiveSpacing.s) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 13))
                .foregroundStyle(ArchivePalette.accentMoss)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: ArchiveSpacing.xs) {
                    Text("生活刻度 · 时光日历图")
                        .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("·")
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Text("共 \(totalCount) 篇散页手稿留痕")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }

            Spacer()

            // 模式切换胶囊
            HStack(spacing: 4) {
                ForEach(CalendarDisplayMode.allCases) { mode in
                    PaperPillButton(
                        title: mode.rawValue,
                        isSelected: displayMode == mode
                    ) {
                        displayMode = mode
                    }
                }
            }
        }
    }

    // MARK: - 1. 月历视界 (Month Calendar View)

    private var monthCalendarView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 月份导航条
            HStack {
                HStack(spacing: 8) {
                    Button {
                        stepMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 24)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("查看上一月")

                    Text("\(String(currentYear)) 年 \(currentMonth) 月")
                        .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Button {
                        stepMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 24)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("查看下一月")

                    if !isCurrentMonthActive {
                        Button {
                            let now = FormatUtils.beijingCurrentYearMonth()
                            currentYear = now.year
                            currentMonth = now.month
                        } label: {
                            Text("回到今月")
                                .font(ArchiveTypography.monoScale(size: 10.5))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ArchivePalette.accentWarm.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // 当月数据快报
                let monthStats = calculateMonthStats(year: currentYear, month: currentMonth)
                HStack(spacing: 12) {
                    Text("当月手稿：\(monthStats.totalEntries) 篇")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Text("活跃天数：\(monthStats.activeDays) 天")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }

            // 星期表头 (周一至周日)
            let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
            HStack(spacing: 4) {
                ForEach(weekdays.indices, id: \.self) { idx in
                    Text(weekdays[idx])
                        .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                        .foregroundStyle(idx >= 5 ? ArchivePalette.accentWarm.opacity(0.85) : ArchivePalette.inkMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)

            // 7 列日历网格
            let cells = generateMonthCalendarCells(year: currentYear, month: currentMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells) { cell in
                    calendarDayCell(cell)
                }
            }
        }
    }

    /// 单个日历格子
    private func calendarDayCell(_ cell: CalendarDayCell) -> some View {
        let isSelected = selectedDate == cell.dateKey
        let count = entryCounts[cell.dateKey, default: 0]
        let style = cellDensityStyle(for: count)

        return Button {
            guard cell.isCurrentMonth else {
                // 点击非当月格子时，自动跳转到对应月份
                if let parts = cell.dateKey.split(separator: "-").map(String.init) as [String]?,
                   parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]) {
                    currentYear = y
                    currentMonth = m
                    selectedDate = cell.dateKey
                }
                return
            }
            if selectedDate == cell.dateKey {
                selectedDate = nil
            } else {
                selectedDate = cell.dateKey
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(cell.dayNumber)")
                        .font(ArchiveTypography.monoScale(size: 11, weight: cell.isToday ? .bold : .regular))
                        .foregroundStyle(
                            cell.isCurrentMonth
                                ? (cell.isToday ? ArchivePalette.accentWarm : ArchivePalette.inkPrimary)
                                : ArchivePalette.inkMuted.opacity(0.4)
                        )
                    Spacer()
                    if count > 0 && cell.isCurrentMonth {
                        Text("\(count)")
                            .font(ArchiveTypography.monoScale(size: 9, weight: .bold))
                            .foregroundStyle(count >= 3 ? Color.white : ArchivePalette.accentMoss)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 0.5)
                            .background(
                                count >= 3
                                    ? ArchivePalette.accentMoss
                                    : ArchivePalette.accentMoss.opacity(0.25)
                            )
                            .clipShape(Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(height: 38)
            .background(
                cell.isCurrentMonth
                    ? style.fill
                    : ArchivePalette.inkMuted.opacity(0.03)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        isSelected
                            ? ArchivePalette.accentWarm
                            : (cell.isToday ? ArchivePalette.accentWarm.opacity(0.8) : style.stroke),
                        lineWidth: isSelected ? 1.8 : (cell.isToday ? 1.2 : style.lineWidth)
                    )
            )
            .contentShape(Rectangle())
            .help("\(cell.dateKey) · \(count) 篇手稿留痕 (点击筛选)")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cell.dateKey)，\(count) 篇手稿留痕")
    }

    // MARK: - 2. 年度全景 (Annual Matrix View)

    private var annualMatrixView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Button {
                        currentYear -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 24)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("查看上一年度")

                    Text("\(String(currentYear)) 年度生活留痕矩阵")
                        .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Button {
                        currentYear += 1
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 24)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("查看下一年度")
                }

                Spacer()

                let yearCount = entryCounts.filter { $0.key.hasPrefix("\(currentYear)") }.values.reduce(0, +)
                Text("全年在册手稿：\(yearCount) 篇")
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            // 12 个月份的迷你月历网格 (4 列 × 3 行)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(1...12, id: \.self) { m in
                    miniMonthGrid(year: currentYear, month: m)
                }
            }
        }
    }

    /// 迷你月历小方块
    private func miniMonthGrid(year: Int, month: Int) -> some View {
        let cells = generateMonthCalendarCells(year: year, month: month)
        let monthCount = cells.filter { $0.isCurrentMonth }.compactMap { entryCounts[$0.dateKey] }.reduce(0, +)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(month) 月")
                    .font(ArchiveTypography.monoScale(size: 11, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                if monthCount > 0 {
                    Text("\(monthCount)")
                        .font(ArchiveTypography.monoScale(size: 9.5))
                        .foregroundStyle(ArchivePalette.accentMoss)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(cells) { cell in
                    let count = entryCounts[cell.dateKey, default: 0]
                    let isSelected = selectedDate == cell.dateKey
                    let style = cellDensityStyle(for: count)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(cell.isCurrentMonth ? style.fill : ArchivePalette.inkMuted.opacity(0.04))
                        .frame(height: 7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1)
                                .stroke(
                                    isSelected
                                        ? ArchivePalette.accentWarm
                                        : (cell.isToday ? ArchivePalette.accentWarm : Color.clear),
                                    lineWidth: isSelected ? 1.2 : 0.6
                                )
                        )
                        .onTapGesture {
                            guard cell.isCurrentMonth else { return }
                            selectedDate = (selectedDate == cell.dateKey) ? nil : cell.dateKey
                        }
                        .help("\(cell.dateKey) · \(count) 篇")
                }
            }
        }
        .padding(8)
        .background(ArchivePalette.archiveSubtle.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
    }

    // MARK: - 3. ECharts 交互画卷 (Interactive ECharts View)

    private var echartsInteractiveView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ECharts 日历坐标系热力图 · \(String(currentYear)) 年")
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Spacer()
                Text("支持拖拽悬停与精确日期交互")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            DiagramWebView(
                htmlContent: DiagramHTMLBuilder.buildCalendarChartHTML(
                    year: currentYear,
                    entryCounts: entryCounts,
                    isDark: colorScheme == .dark
                ),
                onSelectDate: { dateStr in
                    selectedDate = (selectedDate == dateStr) ? nil : dateStr
                }
            )
            .frame(height: 220)
            .background(ArchivePalette.archiveSubtle.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        }
    }

    // MARK: - 底栏色阶图例

    private var footerLegendBar: some View {
        HStack(spacing: 8) {
            if let sel = selectedDate {
                HStack(spacing: 4) {
                    Circle()
                        .fill(ArchivePalette.accentWarm)
                        .frame(width: 6, height: 6)
                    Text("当前聚焦：\(sel) · \(entryCounts[sel, default: 0]) 篇")
                        .font(ArchiveTypography.monoScale(size: 11, weight: .medium))
                        .foregroundStyle(ArchivePalette.accentWarm)

                    Button {
                        selectedDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .buttonStyle(.plain)
                    .help("清空当前日期筛选")
                }
            }

            Spacer()

            Text("岁月留白")
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                .foregroundStyle(ArchivePalette.inkMuted)

            ForEach(0...4, id: \.self) { lvl in
                let style = cellDensityStyle(for: lvl)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(style.fill)
                    .frame(width: 9, height: 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1.5)
                            .stroke(style.stroke, lineWidth: style.lineWidth)
                    )
            }

            Text("笔墨丰盛")
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
        .padding(.top, 2)
    }


    // MARK: - 日历计算辅助模型与纯函数

    private func stepMonth(by step: Int) {
        var newM = currentMonth + step
        var newY = currentYear
        if newM < 1 {
            newM = 12
            newY -= 1
        } else if newM > 12 {
            newM = 1
            newY += 1
        }
        currentMonth = newM
        currentYear = newY
    }

    private func calculateMonthStats(year: Int, month: Int) -> (totalEntries: Int, activeDays: Int) {
        let prefix = String(format: "%04d-%02d", year, month)
        var total = 0
        var activeDays = 0
        for (dateKey, count) in entryCounts where dateKey.hasPrefix(prefix) {
            total += count
            if count > 0 { activeDays += 1 }
        }
        return (total, activeDays)
    }

    private struct CalendarCellDensity {
        let fill: Color
        let stroke: Color
        let lineWidth: CGFloat
    }

    /// 纸墨渐变色阶规范（单色调递增，遵循 diagram-design fill ramp 规则）
    private func cellDensityStyle(for count: Int) -> CalendarCellDensity {
        switch count {
        case 0:
            return CalendarCellDensity(
                fill: ArchivePalette.inkMuted.opacity(0.06),
                stroke: ArchivePalette.inkMuted.opacity(0.16),
                lineWidth: 0.5
            )
        case 1:
            return CalendarCellDensity(
                fill: ArchivePalette.accentMoss.opacity(0.28),
                stroke: ArchivePalette.accentMoss.opacity(0.40),
                lineWidth: 0.5
            )
        case 2:
            return CalendarCellDensity(
                fill: ArchivePalette.accentMoss.opacity(0.55),
                stroke: .clear,
                lineWidth: 0
            )
        case 3:
            return CalendarCellDensity(
                fill: ArchivePalette.accentMoss.opacity(0.78),
                stroke: .clear,
                lineWidth: 0
            )
        default:
            return CalendarCellDensity(
                fill: ArchivePalette.accentMoss,
                stroke: .clear,
                lineWidth: 0
            )
        }
    }

    private struct CalendarDayCell: Identifiable {
        let id: String
        let dateKey: String
        let dayNumber: Int
        let isCurrentMonth: Bool
        let isToday: Bool
    }

    /// 生成给定年月的完整 7 列月历网格（含前后月份补齐）
    private func generateMonthCalendarCells(year: Int, month: Int) -> [CalendarDayCell] {
        let cal = FormatUtils.beijingCalendar
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        comp.day = 1
        guard let firstDayOfMonth = cal.date(from: comp),
              let range = cal.range(of: .day, in: .month, for: firstDayOfMonth) else {
            return []
        }

        let daysInMonth = range.count
        let weekday = cal.component(.weekday, from: firstDayOfMonth)
        // 转换 weekday（周日为 1，周一为 2）到周一排首位（0 ~ 6）
        let leadingPadding = (weekday + 5) % 7

        let todayKey = FormatUtils.beijingDateString(from: Date())
        var cells: [CalendarDayCell] = []

        // 前导日期补齐（上月末尾）
        if leadingPadding > 0, let prevMonthLastDay = cal.date(byAdding: .day, value: -1, to: firstDayOfMonth) {
            let prevRange = cal.range(of: .day, in: .month, for: prevMonthLastDay) ?? (1..<30)
            let prevDaysInMonth = prevRange.count
            for offset in (0..<leadingPadding).reversed() {
                let d = prevDaysInMonth - offset
                let cellDate = cal.date(byAdding: .day, value: -(offset + 1), to: firstDayOfMonth) ?? firstDayOfMonth
                let key = FormatUtils.beijingDateString(from: cellDate)
                cells.append(CalendarDayCell(
                    id: "prev-\(key)",
                    dateKey: key,
                    dayNumber: d,
                    isCurrentMonth: false,
                    isToday: key == todayKey
                ))
            }
        }

        // 当月日期
        for d in 1...daysInMonth {
            let key = String(format: "%04d-%02d-%02d", year, month, d)
            cells.append(CalendarDayCell(
                id: "cur-\(key)",
                dateKey: key,
                dayNumber: d,
                isCurrentMonth: true,
                isToday: key == todayKey
            ))
        }

        // 尾随日期补齐（填满最后一周）
        let totalCells = cells.count
        let trailingPadding = (7 - (totalCells % 7)) % 7
        if trailingPadding > 0, let lastDayOfMonth = cal.date(byAdding: .day, value: daysInMonth - 1, to: firstDayOfMonth) {
            for offset in 1...trailingPadding {
                let cellDate = cal.date(byAdding: .day, value: offset, to: lastDayOfMonth) ?? lastDayOfMonth
                let key = FormatUtils.beijingDateString(from: cellDate)
                cells.append(CalendarDayCell(
                    id: "next-\(key)",
                    dateKey: key,
                    dayNumber: offset,
                    isCurrentMonth: false,
                    isToday: key == todayKey
                ))
            }
        }

        return cells
    }
}
