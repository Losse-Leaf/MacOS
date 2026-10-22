// PaperDateTimePicker.swift
// 纸本日期与时刻选择器组件 (Date Picker / Time Picker / DateTime Picker)
// 职责：四大经典快捷时刻真源、独立纸墨日历选择器、时刻微调器与时空组合包装器，
//       共享同一套「晨 / 午 / 暮 / 夜」时刻表，避免各处漂移。
// 来源：由 Views/Components/PaperComponents.swift 按职责拆分而来，代码逻辑保持原样。

import SwiftUI

// MARK: - 四大经典快捷时刻 (Quick Time Presets)

/// 纸本快捷时刻定义：晨 / 午 / 暮 / 夜
public struct PaperQuickTimePreset: Identifiable, Hashable {
    public let id: String
    /// 完整时刻文案，如「晨 09:00」
    public let title: String
    /// 单字简称，如「晨」，用于紧凑排布
    public let shortTitle: String
    public let hour: Int
    public let minute: Int

    public init(id: String, title: String, shortTitle: String, hour: Int, minute: Int) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.hour = hour
        self.minute = minute
    }
}

/// 四大经典快捷时刻真源：纸本历法弹层、时刻微调器与时空组合选择器共用，
/// 避免三处时刻表各自漂移。
public enum PaperQuickTimePresets {
    public nonisolated(unsafe) static let all: [PaperQuickTimePreset] = [
        PaperQuickTimePreset(id: "morning", title: "晨 09:00", shortTitle: "晨", hour: 9, minute: 0),
        PaperQuickTimePreset(id: "noon", title: "午 12:30", shortTitle: "午", hour: 12, minute: 30),
        PaperQuickTimePreset(id: "dusk", title: "暮 18:00", shortTitle: "暮", hour: 18, minute: 0),
        PaperQuickTimePreset(id: "night", title: "夜 22:00", shortTitle: "夜", hour: 22, minute: 0)
    ]
}

/// 散页古典纸墨风独立日期与时刻选择器 (PaperDatePicker)
/// 严格杜绝 Emoji 与系统原生 Aqua 控件，采用 SF Symbols 矢量图标与纸墨主题月历
/// 支持双级翻页 (<< < YYYY年MM月 > >>，Text(verbatim:) 根绝 2,026 分节逗号)
/// 支持一体化时刻微调刻度 (enableTime: 晨/午/暮/夜 预设与时分步进)
public struct PaperDatePicker: View {
    @Binding public var selection: Date
    public var enableTime: Bool
    public var label: String?
    /// 是否在弹层内展示「晨 / 午 / 暮 / 夜」四大快捷时刻
    public var showTimePresets: Bool

    @State private var isPopoverPresented: Bool = false
    @State private var displayMonthDate: Date = Date()
    @FocusState private var isTriggerFocused: Bool

    public init(
        selection: Binding<Date>,
        enableTime: Bool = false,
        label: String? = nil,
        showTimePresets: Bool = true
    ) {
        self._selection = selection
        self.enableTime = enableTime
        self.label = label
        self.showTimePresets = showTimePresets
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
                .padding(.horizontal, ArchiveSpacing.s)
                .padding(.vertical, 4.5)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                        .stroke(isToday ? ArchivePalette.borderSubtle : ArchivePalette.accentWarm.opacity(0.5), lineWidth: 0.5)
                )
                .paperFocusRing(isFocused: isTriggerFocused, cornerRadius: ArchiveRadius.xs)
            }
            .buttonStyle(.plain)
            .focused($isTriggerFocused)
            .accessibilityLabel(label ?? (enableTime ? "选择日期与时刻" : "选择日期"))
            .accessibilityValue(dateLabelText)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                datePopoverView
            }
        }
    }

    private var datePopoverView: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
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
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.caption))
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
                        .padding(ArchiveSpacing.xs)
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
                        .padding(ArchiveSpacing.xs)
                }
                .buttonStyle(.plain)
                .help("上一月")

                Spacer()

                let comps = cal.dateComponents([.year, .month], from: displayMonthDate)
                Text(verbatim: "\(comps.year ?? 2026) 年 \(String(format: "%02d", comps.month ?? 1)) 月")
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading, weight: .medium))
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
                        .padding(ArchiveSpacing.xs)
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
                        .padding(ArchiveSpacing.xs)
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
            let daySlots = generateDaySlots(for: displayMonthDate)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ArchiveSpacing.xxs), count: 7), spacing: ArchiveSpacing.xs) {
                ForEach(daySlots) { slot in
                    if let dayDate = slot.date {
                        let isSelected = cal.isDate(dayDate, inSameDayAs: selection)
                        let isTodayDate = cal.isDateInToday(dayDate)
                        let dayNum = cal.component(.day, from: dayDate)
                        let dayComps = cal.dateComponents([.year, .month], from: dayDate)

                        Button {
                            updateSelectionDate(to: dayDate)
                            if !enableTime {
                                isPopoverPresented = false
                            }
                        } label: {
                            Text("\(dayNum)")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption, weight: isSelected ? .bold : .regular))
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
                        .accessibilityLabel("\(dayComps.year ?? 2026)年\(dayComps.month ?? 1)月\(dayNum)日")
                        .accessibilityValue(isSelected ? "已选中" : (isTodayDate ? "今天" : "未选中"))
                    } else {
                        Color.clear
                            .frame(width: 26, height: 26)
                            .accessibilityHidden(true)
                    }
                }
            }

            // 时刻刻度盘 (严格对标 Web 端 PaperDatePicker.vue)
            if enableTime {
                Divider().overlay(ArchivePalette.borderSubtle)

                VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)
                            Text("时刻刻度")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }

                        Spacer()

                        // 时分微调器
                        HStack(spacing: ArchiveSpacing.xs) {
                            let currentHour = cal.component(.hour, from: selection)
                            let currentMin = cal.component(.minute, from: selection)

                            HStack(spacing: ArchiveSpacing.xxs) {
                                Button("-") { adjustHour(-1) }
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .padding(.horizontal, ArchiveSpacing.xs)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("提前一小时")
                                Text(String(format: "%02d", currentHour))
                                    .font(ArchiveTypography.monoScale(size: 11.5, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                    .accessibilityLabel("当前小时")
                                    .accessibilityValue(String(format: "%02d", currentHour))
                                Button("+") { adjustHour(1) }
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .padding(.horizontal, ArchiveSpacing.xs)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("推迟一小时")
                            }
                            .padding(.vertical, ArchiveSpacing.xxs)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(":")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkMuted)

                            HStack(spacing: ArchiveSpacing.xxs) {
                                Button("-") { adjustMinute(-5) }
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .padding(.horizontal, ArchiveSpacing.xs)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("提前五分钟")
                                Text(String(format: "%02d", currentMin))
                                    .font(ArchiveTypography.monoScale(size: 11.5, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                    .accessibilityLabel("当前分钟")
                                    .accessibilityValue(String(format: "%02d", currentMin))
                                Button("+") { adjustMinute(5) }
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .padding(.horizontal, ArchiveSpacing.xs)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("推迟五分钟")
                            }
                            .padding(.vertical, ArchiveSpacing.xxs)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    // 4 个快捷时刻标签 (晨 09:00, 午 12:30, 暮 18:00, 夜 22:00)
                    if showTimePresets {
                        HStack(spacing: ArchiveSpacing.xs) {
                            ForEach(PaperQuickTimePresets.all) { preset in
                                Button {
                                    setTime(hour: preset.hour, minute: preset.minute)
                                } label: {
                                    Text(preset.title)
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
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
                                .accessibilityLabel("跳到\(preset.title)")
                            }
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
                .paperButtonFocusRing()
            }
        }
        .padding(ArchiveCardMetrics.padding)
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

    /// 月历网格占位：带稳定 ID 的结构体，替代 `[Date?]` 直接作为 ForEach 标识
    private struct DaySlot: Identifiable {
        let id: Int
        let date: Date?
    }

    private func generateDaySlots(for date: Date) -> [DaySlot] {
        guard let range = cal.range(of: .day, in: .month, for: date),
              let firstDayOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: date)) else {
            return []
        }
        let firstWeekday = cal.component(.weekday, from: firstDayOfMonth) - 1 // 0 (Sunday) to 6
        var slots: [DaySlot] = []
        // 月首之前的空位
        for offset in 0..<firstWeekday {
            slots.append(DaySlot(id: offset, date: nil))
        }
        for day in range {
            let d = cal.date(byAdding: .day, value: day - 1, to: firstDayOfMonth)
            slots.append(DaySlot(id: slots.count, date: d))
        }
        return slots
    }
}

/// 散页古典打字机独立时间微调器 (PaperTimePicker)
/// 严格杜绝 Emoji，采用等宽数字展示精确到分钟的时刻，固定宽度永不折行
public struct PaperTimePicker: View {
    @Binding public var selection: Date
    public var label: String?

    @State private var isPopoverPresented: Bool = false
    @FocusState private var isTriggerFocused: Bool

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
                .padding(.horizontal, ArchiveSpacing.s)
                .padding(.vertical, 4.5)
                .frame(width: 78)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
                .paperFocusRing(isFocused: isTriggerFocused, cornerRadius: ArchiveRadius.xs)
            }
            .buttonStyle(.plain)
            .focused($isTriggerFocused)
            .accessibilityLabel(label ?? "选择时刻")
            .accessibilityValue(timeString)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                timePopoverView
            }
        }
    }

    private var timePopoverView: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
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
            HStack(spacing: ArchiveSpacing.s) {
                // 小时调节
                HStack(spacing: 0) {
                    Button {
                        adjustHour(-1)
                    } label: {
                        Text("-")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("提前一小时")

                    Text(String(format: "%02d", cal.component(.hour, from: selection)))
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .bold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .frame(width: 28, height: 26)
                        .background(ArchivePalette.archivePaper)
                        .accessibilityLabel("当前小时")
                        .accessibilityValue(String(format: "%02d", cal.component(.hour, from: selection)))

                    Button {
                        adjustHour(1)
                    } label: {
                        Text("+")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("推迟一小时")
                }
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                .overlay(RoundedRectangle(cornerRadius: ArchiveRadius.xs).stroke(ArchivePalette.borderSubtle, lineWidth: 0.6))

                Text(":")
                    .font(ArchiveTypography.monoScale(size: 14, weight: .bold))
                    .foregroundStyle(ArchivePalette.inkMuted)

                // 分钟调节 (5分钟步进)
                HStack(spacing: 0) {
                    Button {
                        adjustMinute(-5)
                    } label: {
                        Text("-")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("提前五分钟")

                    Text(String(format: "%02d", cal.component(.minute, from: selection)))
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .bold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .frame(width: 28, height: 26)
                        .background(ArchivePalette.archivePaper)
                        .accessibilityLabel("当前分钟")
                        .accessibilityValue(String(format: "%02d", cal.component(.minute, from: selection)))

                    Button {
                        adjustMinute(5)
                    } label: {
                        Text("+")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 24, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("推迟五分钟")
                }
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                .overlay(RoundedRectangle(cornerRadius: ArchiveRadius.xs).stroke(ArchivePalette.borderSubtle, lineWidth: 0.6))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, ArchiveSpacing.xs)

            // 四大经典快捷时刻纸签 (对齐 PaperDatePicker.vue)
            HStack(spacing: 5) {
                ForEach(PaperQuickTimePresets.all) { preset in
                    timePresetPill(preset)
                }
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
                .paperButtonFocusRing()
            }
        }
        .padding(ArchiveCardMetrics.padding)
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

    private func timePresetPill(_ preset: PaperQuickTimePreset) -> some View {
        Button {
            var comps = cal.dateComponents([.year, .month, .day, .second], from: selection)
            comps.hour = preset.hour
            comps.minute = preset.minute
            if let d = cal.date(from: comps) {
                selection = d
            }
        } label: {
            Text(preset.title)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ArchiveSpacing.xs)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("跳到\(preset.title)")
    }
}

/// 兼容包装器：散页时空组合选择器 (PaperDateTimePicker)
/// 内部自动组合独立的 PaperDatePicker 与 PaperTimePicker，杜绝空间压缩折行
/// `showQuickShortcuts` 控制是否在控件下方直挂「晨 / 午 / 暮 / 夜」四个快捷时刻纸签
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
        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
            // 弹层内不再重复展示快捷时刻（改由下方纸签直挂，避免双份入口）
            PaperDatePicker(selection: $selection, enableTime: true, label: label, showTimePresets: false)

            if showQuickShortcuts {
                HStack(spacing: ArchiveSpacing.xs) {
                    ForEach(PaperQuickTimePresets.all) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            Text(preset.shortTitle)
                                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.body, weight: .medium))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                                .lineLimit(1)
                                .frame(minWidth: 30, minHeight: ArchiveHitTarget.minPointer)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                .overlay(
                                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("跳到\(preset.title)")
                        .accessibilityLabel("跳到\(preset.title)")
                    }
                }
            }
        }
    }

    /// 应用快捷时刻：保留当前年月日，仅替换时分秒
    private func applyPreset(_ preset: PaperQuickTimePreset) {
        let cal = FormatUtils.beijingCalendar
        var comps = cal.dateComponents([.year, .month, .day], from: selection)
        comps.hour = preset.hour
        comps.minute = preset.minute
        comps.second = 0
        if let newDate = cal.date(from: comps) {
            selection = newDate
        }
    }
}
