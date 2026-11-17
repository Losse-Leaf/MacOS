// LifeCalendarChartView.swift
// 生活刻度 · 时光日历图 (Life Calendar Chart)
// 职责：以真实公历月历与高性能 Canvas 年度矩阵呈现生活散页沉淀。

import SwiftUI
import AppKit

/// 日历呈现形态
public enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case monthGrid = "月历视界"
    case annualMatrix = "年度全景"

    public var id: String { rawValue }
}

/// 生活刻度 · 时光日历图视图
public struct LifeCalendarChartView: View {
    public let entryCounts: [String: Int]
    public let totalCount: Int
    @Binding public var selectedDate: String?

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
            headerToolbar

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            Group {
                switch displayMode {
                case .monthGrid:
                    monthCalendarView
                case .annualMatrix:
                    annualMatrixView
                }
            }

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))

            footerLegendBar
        }
        .padding(ArchiveSpacing.m)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
        .paperElevation(1, cornerRadius: ArchiveRadius.md)
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
            HStack {
                HStack(spacing: 8) {
                    Button {
                        stepMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: ArchiveHitTarget.minPointer, height: ArchiveHitTarget.minPointer)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .paperButtonFocusRing(cornerRadius: 14)
                    .accessibilityLabel("上一月")
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
                            .frame(width: ArchiveHitTarget.minPointer, height: ArchiveHitTarget.minPointer)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .paperButtonFocusRing(cornerRadius: 14)
                    .accessibilityLabel("下一月")
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
                        .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                    }
                }

                Spacer()

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

            let cells = Self.monthCalendarCells(year: currentYear, month: currentMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells) { cell in
                    calendarDayCell(cell)
                }
            }
        }
    }

    private func calendarDayCell(_ cell: CalendarDayCell) -> some View {
        let isSelected = selectedDate == cell.dateKey
        let count = entryCounts[cell.dateKey, default: 0]
        let style = cellDensityStyle(for: count)

        return Button {
            guard cell.isCurrentMonth else {
                let parts = cell.dateKey.split(separator: "-").map(String.init)
                if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]) {
                    currentYear = y
                    currentMonth = m
                    selectedDate = cell.dateKey
                }
                return
            }
            selectedDate = (selectedDate == cell.dateKey) ? nil : cell.dateKey
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
                            .foregroundStyle(count >= 3 ? ArchivePalette.archivePaper : ArchivePalette.accentMoss)
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
        .paperButtonFocusRing(cornerRadius: 3)
        .accessibilityLabel("\(cell.dateKey)，\(count) 篇手稿留痕")
    }

    // MARK: - 2. 年度全景 (Annual Matrix View · 12 Canvas 轻量绘制)

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
                            .frame(width: ArchiveHitTarget.minPointer, height: ArchiveHitTarget.minPointer)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .paperButtonFocusRing(cornerRadius: 14)
                    .accessibilityLabel("上一年度")
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
                            .frame(width: ArchiveHitTarget.minPointer, height: ArchiveHitTarget.minPointer)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .paperButtonFocusRing(cornerRadius: 14)
                    .accessibilityLabel("下一年度")
                    .help("查看下一年度")
                }

                Spacer()

                let yearPrefix = "\(currentYear)-"
                let yearCount = entryCounts.reduce(into: 0) { acc, kv in
                    if kv.key.hasPrefix(yearPrefix) { acc += kv.value }
                }
                Text("全年在册手稿：\(yearCount) 篇")
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(1...12, id: \.self) { m in
                    miniMonthCanvasCard(year: currentYear, month: m)
                }
            }
        }
    }

    /// 单个迷你月历卡片：以单一 `Canvas` 替代原先 35~42 个独立 `RoundedRectangle` 子视图，
    /// 全年子视图节点从 ~504 个骤降至 12 个，并收敛为 12 个月度无障碍摘要节点。
    private func miniMonthCanvasCard(year: Int, month: Int) -> some View {
        let cells = Self.monthCalendarCells(year: year, month: month)
        let rowsCount = max(1, cells.count / 7)
        let stats = calculateMonthStats(year: year, month: month)
        let spacing: CGFloat = 2
        let cellHeight: CGFloat = 9.5
        let canvasHeight = CGFloat(rowsCount) * cellHeight + CGFloat(max(0, rowsCount - 1)) * spacing

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                currentMonth = month
                displayMode = .monthGrid
            } label: {
                HStack {
                    Text("\(month) 月")
                        .font(ArchiveTypography.monoScale(size: 11, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Spacer()
                    if stats.totalEntries > 0 {
                        Text("\(stats.totalEntries)")
                            .font(ArchiveTypography.monoScale(size: 9.5))
                            .foregroundStyle(ArchivePalette.accentMoss)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .paperButtonFocusRing(cornerRadius: 2)
            .help("切换至 \(year) 年 \(month) 月详图")

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let cellWidth = max(2, (totalWidth - spacing * 6) / 7)

                Canvas { context, _ in
                    for (index, cell) in cells.enumerated() {
                        let col = index % 7
                        let row = index / 7
                        let rect = CGRect(
                            x: CGFloat(col) * (cellWidth + spacing),
                            y: CGFloat(row) * (cellHeight + spacing),
                            width: cellWidth,
                            height: cellHeight
                        )
                        let path = Path(roundedRect: rect, cornerRadius: 1.5)
                        let count = entryCounts[cell.dateKey, default: 0]
                        let style = cellDensityStyle(for: count)
                        let fill = cell.isCurrentMonth ? style.fill : ArchivePalette.inkMuted.opacity(0.04)
                        context.fill(path, with: .color(fill))

                        let isSelected = selectedDate == cell.dateKey
                        if isSelected || cell.isToday {
                            context.stroke(
                                path,
                                with: .color(ArchivePalette.accentWarm),
                                lineWidth: isSelected ? 1.3 : 0.7
                            )
                        } else if cell.isCurrentMonth && style.lineWidth > 0 {
                            context.stroke(
                                path,
                                with: .color(style.stroke),
                                lineWidth: style.lineWidth
                            )
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        let col = Int(value.location.x / (cellWidth + spacing))
                        let row = Int(value.location.y / (cellHeight + spacing))
                        guard (0..<7).contains(col), (0..<rowsCount).contains(row) else { return }
                        let idx = row * 7 + col
                        guard cells.indices.contains(idx) else { return }
                        let tapped = cells[idx]
                        guard tapped.isCurrentMonth else { return }
                        selectedDate = (selectedDate == tapped.dateKey) ? nil : tapped.dateKey
                    }
                )
            }
            .frame(height: canvasHeight)
        }
        .padding(8)
        .background(ArchivePalette.archiveSubtle.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(year)年\(month)月，共 \(stats.totalEntries) 篇手稿，活跃 \(stats.activeDays) 天")
        .accessibilityHint("点击切换到该月月历详图")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            currentMonth = month
            displayMode = .monthGrid
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
                    .paperButtonFocusRing(cornerRadius: 8)
                    .accessibilityLabel("清空日期筛选")
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
                    .accessibilityHidden(true)
            }

            Text("笔墨丰盛")
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
        .padding(.top, 2)
    }

    // MARK: - 日历计算辅助模型与记忆化网格

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
        let prefix = String(format: "%04d-%02d-", year, month)
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

    private struct CalendarDayCell: Identifiable, Sendable {
        let id: String
        let dateKey: String
        let dayNumber: Int
        let isCurrentMonth: Bool
        let isToday: Bool
    }

    private struct MonthCacheKey: Hashable {
        let year: Int
        let month: Int
        let todayKey: String
    }

    private static let cellsCacheLock = NSLock()
    private nonisolated(unsafe) static var cellsCache: [MonthCacheKey: [CalendarDayCell]] = [:]

    private static func monthCalendarCells(year: Int, month: Int) -> [CalendarDayCell] {
        let todayKey = FormatUtils.beijingDateString(from: Date())
        let cacheKey = MonthCacheKey(year: year, month: month, todayKey: todayKey)
        cellsCacheLock.lock()
        if let cached = cellsCache[cacheKey] {
            cellsCacheLock.unlock()
            return cached
        }
        cellsCacheLock.unlock()

        let generated = buildMonthCalendarCells(year: year, month: month, todayKey: todayKey)
        cellsCacheLock.lock()
        if cellsCache.count > 48 {
            cellsCache.removeAll(keepingCapacity: true)
        }
        cellsCache[cacheKey] = generated
        cellsCacheLock.unlock()
        return generated
    }

    private static func buildMonthCalendarCells(year: Int, month: Int, todayKey: String) -> [CalendarDayCell] {
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
        let leadingPadding = (weekday + 5) % 7

        var cells: [CalendarDayCell] = []
        cells.reserveCapacity(42)

        if leadingPadding > 0, let prevMonthLastDay = cal.date(byAdding: .day, value: -1, to: firstDayOfMonth) {
            let prevRange = cal.range(of: .day, in: .month, for: prevMonthLastDay) ?? (1..<30)
            let prevDaysInMonth = prevRange.count
            let prevYear = cal.component(.year, from: prevMonthLastDay)
            let prevMonth = cal.component(.month, from: prevMonthLastDay)
            for offset in (0..<leadingPadding).reversed() {
                let d = prevDaysInMonth - offset
                let key = String(format: "%04d-%02d-%02d", prevYear, prevMonth, d)
                cells.append(CalendarDayCell(
                    id: "prev-\(key)",
                    dateKey: key,
                    dayNumber: d,
                    isCurrentMonth: false,
                    isToday: key == todayKey
                ))
            }
        }

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

        let trailingPadding = (7 - (cells.count % 7)) % 7
        if trailingPadding > 0 {
            let nextYear = month == 12 ? year + 1 : year
            let nextMonth = month == 12 ? 1 : month + 1
            for offset in 1...trailingPadding {
                let key = String(format: "%04d-%02d-%02d", nextYear, nextMonth, offset)
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
