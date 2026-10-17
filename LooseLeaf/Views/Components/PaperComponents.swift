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

    public init(entryCounts: [String: Int], totalCount: Int, weeksCount: Int = 32) {
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

/// 散页古典纸墨风时间选择器 (PaperDateTimePicker)
/// 彻底替代系统原生丑陋灰块控件，提供打字机等宽时间戳胶囊与快捷时空锚点
public struct PaperDateTimePicker: View {
    @Binding public var selection: Date
    public var label: String?
    public var showQuickShortcuts: Bool

    @State private var isPopoverPresented: Bool = false

    public init(
        selection: Binding<Date>,
        label: String? = nil,
        showQuickShortcuts: Bool = true
    ) {
        self._selection = selection
        self.label = label
        self.showQuickShortcuts = showQuickShortcuts
    }

    private var parsed: FormatUtils.ParsedBeijingDate {
        FormatUtils.formatBeijingDate(selection)
    }

    private var isToday: Bool {
        FormatUtils.beijingCalendar.isDateInToday(selection)
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            Button {
                isPopoverPresented.toggle()
                AudioFeedback.shared.playTink()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 11))
                        .foregroundStyle(isToday ? ArchivePalette.inkMuted : ArchivePalette.accentWarm)

                    Text(parsed.dotDateTime)
                        .font(ArchiveTypography.monoScale(size: 11.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isToday ? ArchivePalette.borderSubtle : ArchivePalette.accentWarm.opacity(0.6), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                pickerPopoverContent
            }

            if !isToday {
                Text("回溯补记")
                    .font(ArchiveTypography.monoScale(size: 10))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(ArchivePalette.accentWarm.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if showQuickShortcuts {
                HStack(spacing: 4) {
                    Button("此刻") {
                        selection = Date()
                        AudioFeedback.shared.playTink()
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .buttonStyle(.plain)
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    Button("昨日") {
                        if let yesterday = FormatUtils.beijingCalendar.date(byAdding: .day, value: -1, to: Date()) {
                            selection = yesterday
                            AudioFeedback.shared.playTink()
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .buttonStyle(.plain)
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
    }

    private var pickerPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("时间刻度印记")
                    .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                Text("北京时间 (UTC+8)")
                    .font(ArchiveTypography.monoScale(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            // 快捷时间胶囊
            HStack(spacing: 6) {
                shortcutPill("现在此时") {
                    selection = Date()
                }
                shortcutPill("今日 09:00") {
                    let cal = FormatUtils.beijingCalendar
                    var comps = cal.dateComponents([.year, .month, .day], from: Date())
                    comps.hour = 9
                    comps.minute = 0
                    if let d = cal.date(from: comps) { selection = d }
                }
                shortcutPill("今日 14:00") {
                    let cal = FormatUtils.beijingCalendar
                    var comps = cal.dateComponents([.year, .month, .day], from: Date())
                    comps.hour = 14
                    comps.minute = 0
                    if let d = cal.date(from: comps) { selection = d }
                }
                shortcutPill("昨日此时") {
                    if let d = FormatUtils.beijingCalendar.date(byAdding: .day, value: -1, to: Date()) {
                        selection = d
                    }
                }
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            DatePicker(
                "",
                selection: $selection,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.timeZone, FormatUtils.beijingTimeZone)
            .tint(ArchivePalette.accentWarm)

            HStack {
                Text(parsed.dotDateTime)
                    .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                    .foregroundStyle(ArchivePalette.accentWarm)

                Spacer()

                Button("完成") {
                    isPopoverPresented = false
                    AudioFeedback.shared.playTink()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }
        }
        .padding(14)
        .frame(width: 290)
        .background(ArchivePalette.archivePaper)
    }

    private func shortcutPill(_ text: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            AudioFeedback.shared.playTink()
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
}
