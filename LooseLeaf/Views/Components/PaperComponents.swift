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
/// 数据源由 AppState.entryCountsByDate 预聚合（记忆缓存），渲染路径零重复遍历
public struct LifeActivityHeatmapView: View {
    public let entryCounts: [String: Int]
    public let totalCount: Int
    public var weeksCount: Int

    public init(entryCounts: [String: Int], totalCount: Int, weeksCount: Int = 32) {
        self.entryCounts = entryCounts
        self.totalCount = totalCount
        self.weeksCount = weeksCount
    }

    public var body: some View {
        let counts = entryCounts
        let cal = FormatUtils.beijingCalendar
        let today = cal.startOfDay(for: Date())
        let todayKey = FormatUtils.beijingDateString(from: today)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("生活刻度 · 最近印记密度")
                    .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Spacer()
                Text("共 \(totalCount) 篇散页")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            HStack(alignment: .top, spacing: 3) {
                ForEach((0..<weeksCount).reversed(), id: \.self) { weekOffset in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { dayOffset in
                            let totalDaysAgo = weekOffset * 7 + (6 - dayOffset)
                            let cellDate = cal.date(byAdding: .day, value: -totalDaysAgo, to: today) ?? today
                            let key = FormatUtils.beijingDateString(from: cellDate)
                            let count = counts[key, default: 0]
                            let isToday = (key == todayKey)

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(cellColor(for: count))
                                .frame(width: 9, height: 9)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .stroke(isToday ? ArchivePalette.accentWarm : Color.clear, lineWidth: 1)
                                )
                                .help("\(key.replacingOccurrences(of: "-", with: ".")) · \(count) 篇记录")
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
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

/// 纸签胶囊按钮 (用于分类切换、标签选择，摒弃系统原生蓝色高亮)
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
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(ArchiveTypography.bodySans(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? ArchivePalette.archivePaper : ArchivePalette.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? ArchivePalette.accentWarm : ArchivePalette.archiveSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: 0.5)
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
            .brightness(isHovering ? 0.018 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovering ? ArchivePalette.borderDivider : Color.clear, lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
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

/// 出版物操作按钮样式 (0.5pt 微墨线 + 陶土赭石高亮)
public struct PaperPrimaryButtonStyle: ButtonStyle {
    public var isProminent: Bool

    public init(isProminent: Bool = true) {
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
            .foregroundStyle(isProminent ? ArchivePalette.archivePaper : ArchivePalette.inkPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isProminent ? ArchivePalette.accentWarm : ArchivePalette.archiveSubtle)
                    .opacity(configuration.isPressed ? 0.84 : 1.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isProminent ? ArchivePalette.accentWarm : ArchivePalette.borderDivider, lineWidth: 0.5)
            )
    }
}
