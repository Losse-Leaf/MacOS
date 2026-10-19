import SwiftUI
import AppKit

/// 岁月留白刻度切线 (Temporal Gap Separator)
/// 遵循 docs/ecosystem.md §4.1.3：当相邻记录跨度 >= 14 天时自动插入留白标注
public struct TemporalGapDivider: View {
    public let days: Int

    public init(days: Int) {
        self.days = days
    }

    public var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(ArchivePalette.borderDivider)
                .frame(height: 0.5)
            Text("—— 历经 \(days) 天的沉默与沉淀 ——")
                .font(ArchiveTypography.editorialSerif(size: 11.5))
                .foregroundStyle(ArchivePalette.inkMuted)
                .fixedSize()
            Rectangle()
                .fill(ArchivePalette.borderDivider)
                .frame(height: 0.5)
        }
        .padding(.vertical, 10)
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

        let cal = FormatUtils.beijingCalendar
        let today = cal.startOfDay(for: Date())
        let todayKey = FormatUtils.beijingDateString(from: today)

        var weeks: [[DayCell]] = []
        for weekOffset in (0..<weeksCount).reversed() {
            var days: [DayCell] = []
            for dayOffset in 0..<7 {
                let totalDaysAgo = weekOffset * 7 + (6 - dayOffset)
                let cellDate = cal.date(byAdding: .day, value: -totalDaysAgo, to: today) ?? today
                let key = FormatUtils.beijingDateString(from: cellDate)
                days.append(DayCell(id: "\(weekOffset)-\(dayOffset)-\(key)", dateKey: key, isToday: key == todayKey))
            }
            weeks.append(days)
        }
        self.precomputedWeeks = weeks
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.dots.scatter")
                    .font(.system(size: 11))
                    .foregroundStyle(ArchivePalette.accentMoss)
                Text("时光生活刻度")
                    .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Text("·")
                    .foregroundStyle(ArchivePalette.inkMuted)
                Text("共 \(totalCount) 篇散页手稿留痕")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                // 1. 月份标尺
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 28) // 留给左侧星期标尺的对齐空间
                    ForEach(Array(stride(from: 0, to: precomputedWeeks.count, by: 8)), id: \.self) { idx in
                        if let firstDay = precomputedWeeks[idx].first {
                            let parts = firstDay.dateKey.split(separator: "-")
                            if parts.count >= 2, let m = Int(parts[1]) {
                                Text("\(m)月")
                                    .font(ArchiveTypography.monoScale(size: 9.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)

                // 2. 星期标尺与 52 周热力图矩阵
                HStack(alignment: .top, spacing: 6) {
                    VStack(spacing: 6) {
                        Text("周一")
                            .font(ArchiveTypography.bodySans(size: 8.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .frame(height: 9)
                        Text("周四")
                            .font(ArchiveTypography.bodySans(size: 8.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .frame(height: 9)
                        Text("周日")
                            .font(ArchiveTypography.bodySans(size: 8.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .frame(height: 9)
                    }
                    .padding(.top, 2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 3) {
                            ForEach(precomputedWeeks.indices, id: \.self) { weekIdx in
                                VStack(spacing: 3) {
                                    ForEach(precomputedWeeks[weekIdx]) { cell in
                                        let count = entryCounts[cell.dateKey, default: 0]
                                        let isSelected = selectedDate == cell.dateKey
                                        Button {
                                            if selectedDate == cell.dateKey {
                                                selectedDate = nil
                                            } else {
                                                selectedDate = cell.dateKey
                                            }
                                        } label: {
                                            RoundedRectangle(cornerRadius: 1.5)
                                                .fill(cellColor(for: count))
                                                .frame(width: 9, height: 9)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 1.5)
                                                        .stroke(isSelected ? ArchivePalette.accentWarm : (cell.isToday ? ArchivePalette.accentWarm.opacity(0.7) : Color.clear), lineWidth: isSelected ? 1.5 : 1)
                                                )
                                                .help("\(cell.dateKey.replacingOccurrences(of: "-", with: ".")) · \(count) 篇手稿留痕")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                // 3. 底部纸墨色阶图例
                HStack(spacing: 6) {
                    Spacer()
                    Text("岁月留白")
                        .font(ArchiveTypography.monoScale(size: 9.5))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    ForEach(0...4, id: \.self) { lvl in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(cellColor(for: lvl))
                            .frame(width: 8, height: 8)
                    }

                    Text("笔墨丰盛")
                        .font(ArchiveTypography.monoScale(size: 9.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .padding(.top, 4)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
        .paperElevation(1)
    }

    private func cellColor(for count: Int) -> Color {
        switch count {
        case 0:
            return ArchivePalette.borderSubtle
        case 1:
            return ArchivePalette.accentMoss.opacity(0.42)
        case 2:
            return ArchivePalette.accentMoss.opacity(0.68)
        case 3:
            return ArchivePalette.accentMoss.opacity(0.86)
        default:
            return ArchivePalette.accentMoss
        }
    }
}

/// 纸签胶囊按钮 (用于分类切换、标签选择，排版杂志风格微高亮)
public struct PaperPillButton: View {
    public let title: String
    public var icon: String?
    public let isSelected: Bool
    public let action: () -> Void

    public init(
        title: String,
        icon: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                }
                Text(title)
                    .font(ArchiveTypography.bodySans(size: 11.5, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? ArchivePalette.accentWarm : ArchivePalette.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .fill(isSelected ? ArchivePalette.accentWarm.opacity(0.12) : ArchivePalette.archiveSubtle.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .stroke(isSelected ? ArchivePalette.accentWarm.opacity(0.35) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 纸面悬停高亮修饰符：轻微提亮 + 描边加深（为 macOS 指针交互提供物理反馈）
public struct PaperHoverModifier: ViewModifier {
    @State private var isHovering = false

    public func body(content: Content) -> some View {
        content
            .brightness(isHovering ? 0.015 : 0)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
    }
}

public extension View {
    /// 纸面悬停反馈（卡片 / 缩略图等可交互面板）
    func paperHover() -> some View {
        modifier(PaperHoverModifier())
    }
}

/// 出版物操作按钮样式 (优雅墨色/纸本微高亮，告别大泥红)
public struct PaperPrimaryButtonStyle: ButtonStyle {
    public var isProminent: Bool

    public init(isProminent: Bool = true) {
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
            .foregroundStyle(isProminent ? ArchivePalette.archivePaper : ArchivePalette.inkPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .fill(isProminent ? ArchivePalette.inkPrimary : ArchivePalette.archivePaper)
                    .opacity(configuration.isPressed ? 0.85 : 1.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .stroke(isProminent ? Color.clear : ArchivePalette.borderSubtle, lineWidth: 0.5)
            )
            .paperElevation(isProminent ? 1 : 0)
    }
}

/// 散页古典纸墨风独立日期与时刻选择器 (PaperDatePicker)
/// 严格杜绝 Emoji 与系统原生 Aqua 控件，采用 SF Symbols 矢量图标与纸墨主题月历
/// 支持双级翻页 (<< < YYYY年MM月 > >>，Text(verbatim:) 根绝 2,026 分节逗号)
/// 支持一体化时刻微调刻度 (enableTime: 晨/午/暮/夜 预设与时分步进)
public struct PaperDatePicker: View {
    @Binding public var selection: Date
    public var enableTime: Bool
    public var label: String?

    @State private var isPopoverPresented: Bool = false
    @State private var displayMonthDate: Date = Date()

    public init(selection: Binding<Date>, enableTime: Bool = false, label: String? = nil) {
        self._selection = selection
        self.enableTime = enableTime
        self.label = label
    }

    private var cal: Calendar { FormatUtils.beijingCalendar }

    private var isToday: Bool {
        cal.isDateInToday(selection)
    }

    private var isYesterday: Bool {
        cal.isDateInYesterday(selection)
    }

    private var dateLabelText: String {
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: selection)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let hh = String(format: "%02d", comps.hour ?? 0)
        let mm = String(format: "%02d", comps.minute ?? 0)

        let baseDate: String
        if isToday {
            baseDate = "\(m)月\(d)日 · 今天"
        } else if isYesterday {
            baseDate = "\(m)月\(d)日 · 昨天"
        } else {
            baseDate = "\(y).\(String(format: "%02d", m)).\(String(format: "%02d", d))"
        }

        if enableTime {
            return "\(baseDate) \(hh):\(mm)"
        }
        return baseDate
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Button {
                displayMonthDate = selection
                isPopoverPresented.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: enableTime ? "clock" : "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(isToday ? ArchivePalette.inkSecondary : ArchivePalette.accentWarm)

                    Text(dateLabelText)
                        .font(ArchiveTypography.monoScale(size: 11.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                        .fixedSize()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isToday ? ArchivePalette.borderSubtle : ArchivePalette.accentWarm.opacity(0.5), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                datePopoverView
            }
        }
    }

    private var datePopoverView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶部快捷时空锚点
            HStack(spacing: 6) {
                shortcutDatePill(enableTime ? "此刻" : "今天") {
                    updateSelectionDate(to: Date())
                }
                shortcutDatePill("昨天") {
                    if let d = cal.date(byAdding: .day, value: -1, to: Date()) {
                        updateSelectionDate(to: d)
                    }
                }
                shortcutDatePill("前天") {
                    if let d = cal.date(byAdding: .day, value: -2, to: Date()) {
                        updateSelectionDate(to: d)
                    }
                }
                Spacer()
                Text(enableTime ? "纸本历法与时刻" : "纸本历法")
                    .font(ArchiveTypography.editorialSerif(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            // 年月双级翻页栏 (<< < YYYY年MM月 > >>，Text(verbatim:) 根绝 2,026 逗号 Bug)
            HStack(spacing: 3) {
                Button {
                    if let prevYear = cal.date(byAdding: .year, value: -1, to: displayMonthDate) {
                        displayMonthDate = prevYear
                    }
                } label: {
                    Image(systemName: "chevron.left.2")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("上一年")

                Button {
                    if let prevMonth = cal.date(byAdding: .month, value: -1, to: displayMonthDate) {
                        displayMonthDate = prevMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("上一月")

                Spacer()

                let comps = cal.dateComponents([.year, .month], from: displayMonthDate)
                Text(verbatim: "\(comps.year ?? 2026) 年 \(String(format: "%02d", comps.month ?? 1)) 月")
                    .font(ArchiveTypography.editorialSerif(size: 13, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Spacer()

                Button {
                    if let nextMonth = cal.date(byAdding: .month, value: 1, to: displayMonthDate) {
                        displayMonthDate = nextMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("下一月")

                Button {
                    if let nextYear = cal.date(byAdding: .year, value: 1, to: displayMonthDate) {
                        displayMonthDate = nextYear
                    }
                } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("下一年")
            }

            // 星期标尺
            HStack(spacing: 0) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { weekDay in
                    Text(weekDay)
                        .font(ArchiveTypography.bodySans(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            // 当月天数网格
            let daysInMonth = generateDaysInMonth(for: displayMonthDate)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(daysInMonth, id: \.self) { dayItem in
                    if let dayDate = dayItem {
                        let isSelected = cal.isDate(dayDate, inSameDayAs: selection)
                        let isTodayDate = cal.isDateInToday(dayDate)
                        let dayNum = cal.component(.day, from: dayDate)

                        Button {
                            updateSelectionDate(to: dayDate)
                            if !enableTime {
                                isPopoverPresented = false
                            }
                        } label: {
                            Text("\(dayNum)")
                                .font(ArchiveTypography.monoScale(size: 11, weight: isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? ArchivePalette.archivePaper : (isTodayDate ? ArchivePalette.accentWarm : ArchivePalette.inkPrimary))
                                .frame(width: 26, height: 26)
                                .background(
                                    Circle()
                                        .fill(isSelected ? ArchivePalette.inkPrimary : (isTodayDate ? ArchivePalette.accentWarm.opacity(0.12) : Color.clear))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(isTodayDate && !isSelected ? ArchivePalette.accentWarm.opacity(0.4) : Color.clear, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(width: 26, height: 26)
                    }
                }
            }

            // 时刻刻度盘 (严格对标 Web 端 PaperDatePicker.vue)
            if enableTime {
                Divider().overlay(ArchivePalette.borderSubtle)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)
                            Text("时刻刻度")
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }

                        Spacer()

                        // 时分微调器
                        HStack(spacing: 4) {
                            let currentHour = cal.component(.hour, from: selection)
                            let currentMin = cal.component(.minute, from: selection)

                            HStack(spacing: 2) {
                                Button("-") { adjustHour(-1) }
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .padding(.horizontal, 4)
                                    .buttonStyle(.plain)
                                Text(String(format: "%02d", currentHour))
                                    .font(ArchiveTypography.monoScale(size: 11.5, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                Button("+") { adjustHour(1) }
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .padding(.horizontal, 4)
                                    .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(":")
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.inkMuted)

                            HStack(spacing: 2) {
                                Button("-") { adjustMinute(-5) }
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .padding(.horizontal, 4)
                                    .buttonStyle(.plain)
                                Text(String(format: "%02d", currentMin))
                                    .font(ArchiveTypography.monoScale(size: 11.5, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                Button("+") { adjustMinute(5) }
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .padding(.horizontal, 4)
                                    .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    // 4 个快捷时刻标签 (晨 09:00, 午 12:30, 暮 18:00, 夜 22:00)
                    HStack(spacing: 4) {
                        ForEach([("晨 09:00", 9, 0), ("午 12:30", 12, 30), ("暮 18:00", 18, 0), ("夜 22:00", 22, 0)], id: \.0) { item in
                            Button {
                                setTime(hour: item.1, minute: item.2)
                            } label: {
                                Text(item.0)
                                    .font(ArchiveTypography.monoScale(size: 9.5))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 3)
                                    .background(ArchivePalette.archiveSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            HStack {
                Text("所选：\(dateLabelText)")
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.accentWarm)

                Spacer()

                Button("确定") {
                    isPopoverPresented = false
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }
        }
        .padding(14)
        .frame(width: enableTime ? 275 : 250)
        .background(ArchivePalette.archivePaper)
    }

    private func shortcutDatePill(_ text: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            if !enableTime {
                isPopoverPresented = false
            }
        } label: {
            Text(text)
                .font(ArchiveTypography.bodySans(size: 10.5))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    private func updateSelectionDate(to newDate: Date) {
        var origComps = cal.dateComponents([.hour, .minute, .second], from: selection)
        let targetComps = cal.dateComponents([.year, .month, .day], from: newDate)
        origComps.year = targetComps.year
        origComps.month = targetComps.month
        origComps.day = targetComps.day
        if let merged = cal.date(from: origComps) {
            selection = merged
        }
    }

    private func adjustHour(_ delta: Int) {
        if let newD = cal.date(byAdding: .hour, value: delta, to: selection) {
            selection = newD
        }
    }

    private func adjustMinute(_ delta: Int) {
        if let newD = cal.date(byAdding: .minute, value: delta, to: selection) {
            selection = newD
        }
    }

    private func setTime(hour: Int, minute: Int) {
        var comps = cal.dateComponents([.year, .month, .day], from: selection)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let newD = cal.date(from: comps) {
            selection = newD
        }
    }

    private func generateDaysInMonth(for date: Date) -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: date),
              let firstDayOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: date)) else {
            return []
        }
        let firstWeekday = cal.component(.weekday, from: firstDayOfMonth) - 1 // 0 (Sunday) to 6
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(d)
            }
        }
        return days
    }
}

/// 散页古典打字机独立时间微调器 (PaperTimePicker)
/// 严格杜绝 Emoji，采用等宽数字展示精确到分钟的时刻，固定宽度永不折行
public struct PaperTimePicker: View {
    @Binding public var selection: Date
    public var label: String?

    @State private var isPopoverPresented: Bool = false

    public init(selection: Binding<Date>, label: String? = nil) {
        self._selection = selection
        self.label = label
    }

    private var cal: Calendar { FormatUtils.beijingCalendar }

    private var timeString: String {
        let hour = cal.component(.hour, from: selection)
        let minute = cal.component(.minute, from: selection)
        return String(format: "%02d:%02d", hour, minute)
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Button {
                isPopoverPresented.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkSecondary)

                    Text(timeString)
                        .font(ArchiveTypography.monoScale(size: 11.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                        .fixedSize()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .frame(width: 78)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                timePopoverView
            }
        }
    }

    private var timePopoverView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    Text("时刻刻度")
                        .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                Spacer()

                Button("设为此刻") {
                    let now = Date()
                    let nowComps = cal.dateComponents([.hour, .minute, .second], from: now)
                    var curComps = cal.dateComponents([.year, .month, .day], from: selection)
                    curComps.hour = nowComps.hour
                    curComps.minute = nowComps.minute
                    curComps.second = nowComps.second
                    if let updated = cal.date(from: curComps) {
                        selection = updated
                    }
                }
                .font(ArchiveTypography.bodySans(size: 10.5))
                .buttonStyle(.plain)
                .foregroundStyle(ArchivePalette.accentWarm)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(ArchivePalette.accentWarm.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            // 自定步进微调器（- HH + 与 - MM +）彻底替换系统原生 Picker 菜单
            HStack(spacing: 8) {
                // 小时调节
                HStack(spacing: 0) {
                    Button {
                        adjustHour(-1)
                    } label: {
                        Text("-")
                            .font(ArchiveTypography.monoScale(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(String(format: "%02d", cal.component(.hour, from: selection)))
                        .font(ArchiveTypography.monoScale(size: 13, weight: .bold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .frame(width: 28, height: 26)
                        .background(ArchivePalette.archivePaper)

                    Button {
                        adjustHour(1)
                    } label: {
                        Text("+")
                            .font(ArchiveTypography.monoScale(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.borderSubtle, lineWidth: 0.6))

                Text(":")
                    .font(ArchiveTypography.monoScale(size: 14, weight: .bold))
                    .foregroundStyle(ArchivePalette.inkMuted)

                // 分钟调节 (5分钟步进)
                HStack(spacing: 0) {
                    Button {
                        adjustMinute(-5)
                    } label: {
                        Text("-")
                            .font(ArchiveTypography.monoScale(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(String(format: "%02d", cal.component(.minute, from: selection)))
                        .font(ArchiveTypography.monoScale(size: 13, weight: .bold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .frame(width: 28, height: 26)
                        .background(ArchivePalette.archivePaper)

                    Button {
                        adjustMinute(5)
                    } label: {
                        Text("+")
                            .font(ArchiveTypography.monoScale(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.borderSubtle, lineWidth: 0.6))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)

            // 四大经典快捷时刻纸签 (对齐 PaperDatePicker.vue)
            HStack(spacing: 5) {
                timePresetPill("晨 09:00", hour: 9, minute: 0)
                timePresetPill("午 12:30", hour: 12, minute: 30)
                timePresetPill("暮 18:00", hour: 18, minute: 0)
                timePresetPill("夜 22:00", hour: 22, minute: 0)
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            HStack {
                Text("时刻：\(timeString)")
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)

                Spacer()

                Button("完成") {
                    isPopoverPresented = false
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(ArchivePalette.archivePaper)
    }

    private func adjustHour(_ delta: Int) {
        var hour = cal.component(.hour, from: selection) + delta
        hour = (hour % 24 + 24) % 24
        var comps = cal.dateComponents([.year, .month, .day, .minute, .second], from: selection)
        comps.hour = hour
        if let d = cal.date(from: comps) {
            selection = d
        }
    }

    private func adjustMinute(_ delta: Int) {
        var minute = cal.component(.minute, from: selection) + delta
        minute = (minute % 60 + 60) % 60
        var comps = cal.dateComponents([.year, .month, .day, .hour, .second], from: selection)
        comps.minute = minute
        if let d = cal.date(from: comps) {
            selection = d
        }
    }

    private func timePresetPill(_ label: String, hour: Int, minute: Int) -> some View {
        Button {
            var comps = cal.dateComponents([.year, .month, .day, .second], from: selection)
            comps.hour = hour
            comps.minute = minute
            if let d = cal.date(from: comps) {
                selection = d
            }
        } label: {
            Text(label)
                .font(ArchiveTypography.monoScale(size: 9.5))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/// 兼容包装器：散页时空组合选择器 (PaperDateTimePicker)
/// 内部自动组合独立的 PaperDatePicker 与 PaperTimePicker，杜绝空间压缩折行
public struct PaperDateTimePicker: View {
    @Binding public var selection: Date
    public var label: String?
    public var showQuickShortcuts: Bool

    public init(
        selection: Binding<Date>,
        label: String? = nil,
        showQuickShortcuts: Bool = true
    ) {
        self._selection = selection
        self.label = label
        self.showQuickShortcuts = showQuickShortcuts
    }

    public var body: some View {
        PaperDatePicker(selection: $selection, enableTime: true, label: label)
    }
}

/// 纸质拟物省市行政区划点选器 (PaperCityPicker)
/// 严格遵循要求：地点只选省市、拒绝复杂打字、杜绝 Emoji、支持 macOS 原生定位一键秒选
public struct PaperCityPicker: View {
    @Binding public var selectedCode: String
    @Binding public var selectedName: String
    public var placeholder: String
    public var label: String?
    public var isFullWidth: Bool

    @State private var isPickerPresented: Bool = false
    @State private var searchKeyword: String = ""
    @State private var activeProvince: String = "北京"

    public init(
        selectedCode: Binding<String>,
        selectedName: Binding<String>,
        placeholder: String = "选择省市…",
        label: String? = nil,
        isFullWidth: Bool = false
    ) {
        self._selectedCode = selectedCode
        self._selectedName = selectedName
        self.placeholder = placeholder
        self.label = label
        self.isFullWidth = isFullWidth
    }

    private var displayText: String {
        if !selectedName.isEmpty {
            if !selectedCode.isEmpty {
                let prefix = String(selectedCode.prefix(2))
                let prov = CityDictionary.provincePrefixMap[prefix] ?? ""
                let provText = prov.isEmpty || selectedName.contains(prov) ? "" : "\(prov) · "
                return "\(provText)\(selectedName)"
            }
            return selectedName
        }
        return placeholder
    }

    private var isSelected: Bool {
        !selectedName.isEmpty || !selectedCode.isEmpty
    }

    /// 省名列表只计算一次（此前每次 body 求值都重建 Set + 排序）
    private static let allProvincesCache: [String] = Array(Set(CityDictionary.provincePrefixMap.values)).sorted()

    private var allProvinces: [String] {
        Self.allProvincesCache
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label)
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            // 外层不再用 Button 包裹：内部「清除」若嵌在 Button 里会同时触发打开弹层（双动作）
            HStack(spacing: 5) {
                Image(systemName: "map")
                    .font(.system(size: 10.5))
                    .foregroundStyle(isSelected ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)

                Text(displayText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(isSelected ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                    .lineLimit(1)

                if isFullWidth {
                    Spacer(minLength: 4)
                }

                if isSelected {
                    Button {
                        selectedCode = ""
                        selectedName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除已选城市")
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                searchKeyword = ""
                if let firstProv = allProvinces.first, activeProvince.isEmpty {
                    activeProvince = firstProv
                }
                // 已授权时静默刷新定位；未授权不在打开弹层的瞬间突然弹权限框
                if LocationManager.shared.isAuthorized {
                    LocationManager.shared.fetchCurrentLocation()
                }
                isPickerPresented = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("选择省市，当前为 \(displayText)")
            .padding(.horizontal, 8)
            .padding(.vertical, isFullWidth ? 7 : 4.5)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? ArchivePalette.accentWarm.opacity(0.4) : ArchivePalette.borderDivider, lineWidth: 0.5)
            )
            .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
                cityPopoverContent
            }
        }
    }

    private var cityPopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. 顶部当前定位秒选卡片
            let locMgr = LocationManager.shared
            if !locMgr.currentCity.isEmpty {
                Button {
                    let resolvedName = locMgr.currentCity
                    if let code = CityDictionary.code(forLocation: resolvedName) {
                        selectedCode = code
                        selectedName = resolvedName
                    } else {
                        selectedName = resolvedName
                    }
                    isPickerPresented = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text("当前定位：\(locMgr.lastResolvedLocationName)")
                            .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .lineLimit(1)
                        Spacer()
                        Text("点击选用")
                            .font(ArchiveTypography.bodySans(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(ArchivePalette.accentWarm.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            } else {
                // 未定位成功时才提供显式入口：把权限申请收敛到用户主动点击，避免开弹层即弹系统框
                Button {
                    let status = locMgr.authorizationStatus
                    if status == .denied || status == .restricted {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                            NSWorkspace.shared.open(url)
                        }
                    } else {
                        locMgr.requestAuthorizationAndFetch()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location")
                            .font(.system(size: 10))
                        Text(locMgr.authorizationStatus == .denied || locMgr.authorizationStatus == .restricted
                             ? "定位权限已关闭 · 去系统设置开启"
                             : "使用当前定位")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                        Spacer()
                    }
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            // 2. 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("检索省份或地级市…", text: $searchKeyword)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 11.5))
            }
            .padding(6)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Divider().overlay(ArchivePalette.borderSubtle)

            // 3. 内容展示：搜索模式 vs 两级省市点选模式
            if !searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let filtered = CityDictionary.searchCities(searchKeyword)
                if filtered.isEmpty {
                    Text("未检索到匹配的省市")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filtered) { city in
                                Button {
                                    selectedCode = city.code
                                    selectedName = city.name
                                    isPickerPresented = false
                                } label: {
                                    HStack {
                                        Text("\(city.province) · \(city.name)")
                                            .font(ArchiveTypography.bodySans(size: 11.5))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 200)
                }
            } else {
                // 两级联动省市选择面板 (免键盘纯点选)
                HStack(spacing: 0) {
                    // 左侧省份列表
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(allProvinces, id: \.self) { prov in
                                let isProvActive = prov == activeProvince
                                Button {
                                    activeProvince = prov
                                } label: {
                                    HStack {
                                        Text(prov)
                                            .font(ArchiveTypography.bodySans(size: 11, weight: isProvActive ? .semibold : .regular))
                                            .foregroundStyle(isProvActive ? ArchivePalette.accentWarm : ArchivePalette.inkPrimary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isProvActive ? ArchivePalette.accentWarm.opacity(0.12) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(width: 85, height: 210)

                    Rectangle()
                        .fill(ArchivePalette.borderSubtle)
                        .frame(width: 0.5)
                        .padding(.vertical, 2)

                    // 右侧地级市列表
                    let citiesInProv = CityDictionary.standardCities.filter { $0.province == activeProvince }
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(citiesInProv) { city in
                                Button {
                                    selectedCode = city.code
                                    selectedName = city.name
                                    isPickerPresented = false
                                } label: {
                                    HStack {
                                        Text(city.name)
                                            .font(ArchiveTypography.bodySans(size: 11.5))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8))
                                            .foregroundStyle(selectedCode == city.code ? ArchivePalette.accentWarm : Color.clear)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(width: 140, height: 210)
                }
            }
        }
        .padding(10)
        .frame(width: 250)
        .background(ArchivePalette.archivePaper)
    }
}

// MARK: - 纸本拟物下拉单选器 (PaperSelect) 与 分段选择器 (PaperSegmentedControl)

/// 纸本选项定义 (严格对标 Web 端 PaperSelectOption)
public struct PaperSelectOption<T: Hashable & Sendable>: Identifiable, Equatable, Sendable {
    public let value: T
    public let label: String
    public let sublabel: String?
    public let badge: String?

    public var id: T { value }

    public init(value: T, label: String, sublabel: String? = nil, badge: String? = nil) {
        self.value = value
        self.label = label
        self.sublabel = sublabel
        self.badge = badge
    }
}

/// 纸本拟物下拉单选器 (PaperSelect)
/// 严格 1:1 对标 Web 端 PaperSelect.vue，彻底杜绝系统 Aqua 液态玻璃原生菜单
/// 包含边框拟物、展开旋转 Chevron、纸本浮层、点选 Checkmark 标定、Tink 触觉音效
public struct PaperSelect<T: Hashable & Sendable>: View {
    @Binding public var selection: T
    public var options: [PaperSelectOption<T>]
    public var placeholder: String
    public var label: String?
    public var disabled: Bool

    @State private var isOpen: Bool = false

    public init(
        selection: Binding<T>,
        options: [PaperSelectOption<T>],
        placeholder: String = "请选择…",
        label: String? = nil,
        disabled: Bool = false
    ) {
        self._selection = selection
        self.options = options
        self.placeholder = placeholder
        self.label = label
        self.disabled = disabled
    }

    private var selectedOption: PaperSelectOption<T>? {
        options.first { $0.value == selection }
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Button {
                guard !disabled else { return }
                isOpen.toggle()
            } label: {
                HStack(spacing: 5) {
                    if let selectedOption {
                        Text(selectedOption.label)
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                            .lineLimit(1)
                    } else {
                        Text(placeholder)
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(isOpen ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .animation(.easeInOut(duration: 0.18), value: isOpen)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isOpen ? ArchivePalette.inkPrimary : ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1.0)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if options.isEmpty {
                        Text("暂无可选项")
                            .font(ArchiveTypography.editorialSerif(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(options) { opt in
                                    let isSelected = opt.value == selection
                                    Button {
                                        selection = opt.value
                                        isOpen = false
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(opt.label)
                                                .font(ArchiveTypography.bodySans(size: 11.5, weight: isSelected ? .medium : .regular))
                                                .foregroundStyle(ArchivePalette.inkPrimary)
                                                .lineLimit(1)

                                            if let sub = opt.sublabel, !sub.isEmpty {
                                                Text(sub)
                                                    .font(ArchiveTypography.monoScale(size: 10))
                                                    .foregroundStyle(ArchivePalette.inkMuted)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            if let badge = opt.badge, !badge.isEmpty {
                                                Text(badge)
                                                    .font(ArchiveTypography.monoScale(size: 9))
                                                    .foregroundStyle(ArchivePalette.inkMuted)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(ArchivePalette.archiveSubtle)
                                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                            }

                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 8.5, weight: .bold))
                                                    .foregroundStyle(ArchivePalette.accentWarm)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? ArchivePalette.archiveSubtle : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .padding(6)
                .frame(minWidth: 140, maxWidth: 260)
                .background(ArchivePalette.archivePaper)
            }
        }
    }
}

/// 纸本分段切换器 (PaperSegmentedControl)
/// 彻底替代系统的 .pickerStyle(.segmented)，提供纯粹纸墨灰阶反白与触感反馈
public struct PaperSegmentItem<T: Hashable>: Identifiable, Equatable {
    public let value: T
    public let title: String
    public let icon: String?

    public var id: T { value }

    public init(_ value: T, title: String, icon: String? = nil) {
        self.value = value
        self.title = title
        self.icon = icon
    }
}

public struct PaperSegmentedControl<T: Hashable>: View {
    @Binding public var selection: T
    public var items: [PaperSegmentItem<T>]

    public init(selection: Binding<T>, items: [PaperSegmentItem<T>]) {
        self._selection = selection
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(items) { item in
                let isSelected = item.value == selection
                Button {
                    guard item.value != selection else { return }
                    selection = item.value
                } label: {
                    HStack(spacing: 4) {
                        if let icon = item.icon {
                            Image(systemName: icon)
                                .font(.system(size: 10.5))
                        }
                        Text(item.title)
                            .font(ArchiveTypography.bodySans(size: 11.5, weight: isSelected ? .medium : .regular))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(isSelected ? ArchivePalette.archivePaper : ArchivePalette.inkSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(isSelected ? ArchivePalette.inkPrimary : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.12), value: selection)
            }
        }
        .padding(2.5)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }
}

// MARK: - 纸本复选框与滑动开关样式 (Paper Checkbox & Switch Toggle Styles)

/// 纸本复选框样式 (PaperCheckboxToggleStyle)
/// 替代系统 macOS 蓝白复选框，遵循极简纸墨美学与触感反馈
public struct PaperCheckboxToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3.5)
                        .stroke(configuration.isOn ? ArchivePalette.inkPrimary : ArchivePalette.borderSubtle, lineWidth: 1.2)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(configuration.isOn ? ArchivePalette.inkPrimary : ArchivePalette.archivePaper)
                        )
                        .frame(width: 15, height: 15)

                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(ArchivePalette.archivePaper)
                    }
                }

                configuration.label
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkPrimary)
            }
        }
        .buttonStyle(.plain)
    }
}

public extension ToggleStyle where Self == PaperCheckboxToggleStyle {
    static var paperCheckbox: PaperCheckboxToggleStyle { PaperCheckboxToggleStyle() }
}

/// 纸本滑动开关样式 (PaperSwitchToggleStyle)
/// 替代系统 macOS 绿色开关，支持平滑弹性过渡与纸墨底色
public struct PaperSwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                configuration.label

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(configuration.isOn ? ArchivePalette.accentWarm : ArchivePalette.archiveSubtle)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(configuration.isOn ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: 1)
                        )
                        .frame(width: 34, height: 18)

                    Circle()
                        .fill(ArchivePalette.archivePaper)
                        .shadow(color: Color.black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                        .frame(width: 14, height: 14)
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

public extension ToggleStyle where Self == PaperSwitchToggleStyle {
    static var paperSwitch: PaperSwitchToggleStyle { PaperSwitchToggleStyle() }
}


// MARK: - 纸张物理微投影（原在 Models/ArchiveTokens.swift，属于视图层）

/// 纸张物理微投影修饰符（取代死板 0.5pt 灰色硬边框）
public struct PaperElevationModifier: ViewModifier {
    public var level: Int

    public func body(content: Content) -> some View {
        switch level {
        case 1:
            content
                .shadow(color: Color.black.opacity(0.025), radius: 1, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.035), radius: 6, x: 0, y: 2)
        case 2:
            content
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 2)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        default:
            content
        }
    }
}

public extension View {
    /// 纸张物理轻微投影
    func paperElevation(_ level: Int = 1) -> some View {
        modifier(PaperElevationModifier(level: level))
    }
}
