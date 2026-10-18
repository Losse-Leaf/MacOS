import SwiftUI

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

    private struct DayCell: Identifiable {
        let id: String
        let dateKey: String
        let isToday: Bool
    }

    private let precomputedWeeks: [[DayCell]]

    public init(entryCounts: [String: Int], totalCount: Int, weeksCount: Int = 52) {
        self.entryCounts = entryCounts
        self.totalCount = totalCount
        self.weeksCount = weeksCount

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

    @State private var isExpanded: Bool = false

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

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                    AudioFeedback.shared.playPaperFlip()
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起星野" : "展开刻度网格")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(ArchivePalette.archiveSubtle.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(precomputedWeeks.indices, id: \.self) { weekIdx in
                        VStack(spacing: 3) {
                            ForEach(precomputedWeeks[weekIdx]) { cell in
                                let count = entryCounts[cell.dateKey, default: 0]
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(cellColor(for: count))
                                    .frame(width: 9, height: 9)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .stroke(cell.isToday ? ArchivePalette.accentWarm : Color.clear, lineWidth: 1)
                                    )
                                    .help("\(cell.dateKey.replacingOccurrences(of: "-", with: ".")) · \(count) 篇记录")
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
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

/// 散页古典纸墨风独立日期选择器 (PaperDatePicker)
/// 严格杜绝 Emoji，采用 SF Symbols 矢量图标与纸墨主题月历，支持快捷时空锚点与整月网格点选
public struct PaperDatePicker: View {
    @Binding public var selection: Date
    public var label: String?

    @State private var isPopoverPresented: Bool = false
    @State private var displayMonthDate: Date = Date()

    public init(selection: Binding<Date>, label: String? = nil) {
        self._selection = selection
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
        let comps = cal.dateComponents([.year, .month, .day], from: selection)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1

        if isToday {
            return "\(m)月\(d)日 · 今天"
        } else if isYesterday {
            return "\(m)月\(d)日 · 昨天"
        } else {
            return "\(y).\(String(format: "%02d", m)).\(String(format: "%02d", d))"
        }
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
                AudioFeedback.shared.playTink()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
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
                shortcutDatePill("今天") {
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
                Text("纸本历法")
                    .font(ArchiveTypography.editorialSerif(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            // 月历翻页栏
            HStack {
                Button {
                    if let prevMonth = cal.date(byAdding: .month, value: -1, to: displayMonthDate) {
                        displayMonthDate = prevMonth
                        AudioFeedback.shared.playTink()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(4)
                }
                .buttonStyle(.plain)

                Spacer()

                let comps = cal.dateComponents([.year, .month], from: displayMonthDate)
                Text("\(comps.year ?? 2026) 年 \(comps.month ?? 1) 月")
                    .font(ArchiveTypography.editorialSerif(size: 13, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Spacer()

                Button {
                    if let nextMonth = cal.date(byAdding: .month, value: 1, to: displayMonthDate) {
                        displayMonthDate = nextMonth
                        AudioFeedback.shared.playTink()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
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
                            AudioFeedback.shared.playTink()
                            isPopoverPresented = false
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

            Divider().overlay(ArchivePalette.borderSubtle)

            HStack {
                Text("所选：\(dateLabelText)")
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.accentWarm)

                Spacer()

                Button("确定") {
                    isPopoverPresented = false
                    AudioFeedback.shared.playTink()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }
        }
        .padding(14)
        .frame(width: 250)
        .background(ArchivePalette.archivePaper)
    }

    private func shortcutDatePill(_ text: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            AudioFeedback.shared.playTink()
            isPopoverPresented = false
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
                AudioFeedback.shared.playTink()
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("精准时刻 (分)")
                    .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)

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
                    AudioFeedback.shared.playTink()
                }
                .font(ArchiveTypography.bodySans(size: 10.5))
                .buttonStyle(.plain)
                .foregroundStyle(ArchivePalette.accentWarm)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(ArchivePalette.accentWarm.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            // 快捷加减分钟
            HStack(spacing: 6) {
                stepMinuteButton(delta: -15, label: "-15分")
                stepMinuteButton(delta: -5, label: "-5分")
                stepMinuteButton(delta: 5, label: "+5分")
                stepMinuteButton(delta: 15, label: "+15分")
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            // 小时与分钟直接微调
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("时")
                        .font(ArchiveTypography.bodySans(size: 10))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Picker("", selection: Binding(
                        get: { cal.component(.hour, from: selection) },
                        set: { newHour in
                            var comps = cal.dateComponents([.year, .month, .day, .minute, .second], from: selection)
                            comps.hour = newHour
                            if let d = cal.date(from: comps) { selection = d }
                        }
                    )) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 58)
                }

                Text(":")
                    .font(ArchiveTypography.monoScale(size: 14, weight: .bold))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .padding(.top, 14)

                VStack(spacing: 4) {
                    Text("分")
                        .font(ArchiveTypography.bodySans(size: 10))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Picker("", selection: Binding(
                        get: { cal.component(.minute, from: selection) },
                        set: { newMinute in
                            var comps = cal.dateComponents([.year, .month, .day, .hour, .second], from: selection)
                            comps.minute = newMinute
                            if let d = cal.date(from: comps) { selection = d }
                        }
                    )) {
                        ForEach(0..<60, id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 58)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)

            HStack {
                Spacer()
                Button("完成") {
                    isPopoverPresented = false
                    AudioFeedback.shared.playTink()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }
        }
        .padding(12)
        .frame(width: 200)
        .background(ArchivePalette.archivePaper)
    }

    private func stepMinuteButton(delta: Int, label: String) -> some View {
        Button {
            if let updated = cal.date(byAdding: .minute, value: delta, to: selection) {
                selection = updated
                AudioFeedback.shared.playTink()
            }
        } label: {
            Text(label)
                .font(ArchiveTypography.monoScale(size: 10))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 3))
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
        HStack(spacing: 6) {
            PaperDatePicker(selection: $selection, label: label)
            PaperTimePicker(selection: $selection)
        }
    }
}

/// 纸质拟物省市行政区划点选器 (PaperCityPicker)
/// 严格遵循要求：地点只选省市、拒绝复杂打字、杜绝 Emoji、支持 macOS 原生定位一键秒选
public struct PaperCityPicker: View {
    @Binding public var selectedCode: String
    @Binding public var selectedName: String
    public var placeholder: String

    @State private var isPickerPresented: Bool = false
    @State private var searchKeyword: String = ""
    @State private var activeProvince: String = "北京"

    public init(
        selectedCode: Binding<String>,
        selectedName: Binding<String>,
        placeholder: String = "选择省市…"
    ) {
        self._selectedCode = selectedCode
        self._selectedName = selectedName
        self.placeholder = placeholder
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

    private var allProvinces: [String] {
        let values = Array(Set(CityDictionary.provincePrefixMap.values)).sorted()
        return values
    }

    public var body: some View {
        Button {
            searchKeyword = ""
            if let firstProv = allProvinces.first, activeProvince.isEmpty {
                activeProvince = firstProv
            }
            // 尝试静默请求原生定位
            LocationManager.shared.requestAuthorizationAndFetch()
            isPickerPresented = true
            AudioFeedback.shared.playTink()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "map")
                    .font(.system(size: 10.5))
                    .foregroundStyle(isSelected ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)

                Text(displayText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(isSelected ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                    .lineLimit(1)

                if isSelected {
                    Button {
                        selectedCode = ""
                        selectedName = ""
                        AudioFeedback.shared.playTink()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .buttonStyle(.plain)
                }

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
                    .stroke(isSelected ? ArchivePalette.accentWarm.opacity(0.4) : ArchivePalette.borderDivider, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            cityPopoverContent
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
                    AudioFeedback.shared.playTink()
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
                                    AudioFeedback.shared.playTink()
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
                                    AudioFeedback.shared.playTink()
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
                                    AudioFeedback.shared.playTink()
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
