import SwiftUI
import AppKit

// MARK: - 造物项目状态语义 (Project Status)

/// 造物项目状态语义字典（全应用唯一真源）。
/// 四端统一为中文四态（与后端 validProjectStatuses 白名单一致）；
/// 存量英文/历史表述由 normalize 兼容读取。
public enum ProjectStatus: String, CaseIterable, Identifiable, Sendable {
    case inProgress = "进行中"
    case completed = "已完成"
    case maintaining = "维护中"
    case shelved = "已搁置"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public var isActiveLike: Bool {
        switch self {
        case .inProgress, .maintaining: return true
        case .completed, .shelved: return false
        }
    }

    public static func normalize(_ raw: String?) -> ProjectStatus {
        guard let raw, !raw.isEmpty else { return .inProgress }
        if let matched = ProjectStatus(rawValue: raw) {
            return matched
        }
        switch raw.lowercased() {
        case "active", "wip": return .inProgress
        case "maintained", "持续维护": return .maintaining
        case "archived", "已归档": return .shelved
        default: return .inProgress
        }
    }

    public static func matches(_ raw: String?, selected: String) -> Bool {
        if selected == "all" { return true }
        return normalize(raw).rawValue == selected
    }
}

/// 城市 / 省份回忆抽屉的选择载荷（TravelAtlasView 与抽屉 Sheet 共用）
public struct DrawerCitySelection: Identifiable, Equatable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

/// 统一样式与等高对齐的心愿典藏卡片 (WishCardView)
struct WishCardView: View {
    let wish: Wish
    var isHighlighted: Bool = false
    let onResolve: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private enum CardAction: Hashable {
        case edit, delete
    }

    @State private var isHovering: Bool = false
    @FocusState private var focusedAction: CardAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 顶栏：分类标签徽章 + 私密徽标 + 状态微胶囊
            HStack(alignment: .center, spacing: 6) {
                HStack(spacing: ArchiveSpacing.xs) {
                    Image(systemName: kindIcon)
                        .font(.system(size: 10))
                    Text(kindTitle)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                }
                .foregroundStyle(kindColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(kindColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                if wish.isPrivate == true {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text("私密")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    }
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .accessibilityLabel("私密心愿")
                }

                Spacer()

                HStack(spacing: ArchiveSpacing.xs) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 5.5, height: 5.5)
                    Text(statusTitle)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                        .foregroundStyle(statusTextColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(statusBgColor)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            }
            .padding(.bottom, 10)

            // 2. 标题
            Text(wish.title)
                .font(ArchiveTypography.editorialSerif(size: 16.5, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)

            // 3. 规格 / 目的地
            if let city = wish.cityName, !city.isEmpty, wish.kind == "travel" {
                HStack(spacing: ArchiveSpacing.xs) {
                    Image(systemName: ArchiveIcon.location.systemName)
                        .font(.system(size: 10))
                    Text(city)
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption, weight: .medium))
                }
                .foregroundStyle(ArchivePalette.inkSecondary)
                .padding(.top, 3)
                .lineLimit(1)
            }

            if let spec = wish.spec, !spec.isEmpty {
                HStack(spacing: ArchiveSpacing.xs) {
                    Image(systemName: "slider.horizontal.2")
                        .font(.system(size: 10))
                    Text(spec)
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption, weight: .medium))
                }
                .foregroundStyle(ArchivePalette.inkSecondary)
                .padding(.top, 3)
                .lineLimit(1)
            }

            // 4. 手记备注（走安全富文本视图，杜绝 LocalizedStringKey 格式化解析隐患）
            if let note = wish.note, !note.isEmpty {
                EditorialProseTextView(
                    note,
                    font: ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body),
                    color: ArchivePalette.inkSecondary.opacity(0.88),
                    lineSpacing: 2,
                    lineLimit: 2
                )
                .padding(.top, 4)
            }

            Spacer(minLength: 12)

            // 5. 分割线
            Rectangle()
                .fill(ArchivePalette.borderDivider)
                .frame(height: 0.5)
                .padding(.vertical, 9)

            // 6. 底部：预算 / 实付金额 + 操作按钮栏
            HStack(alignment: .center) {
                if wish.status == "fulfilled" && wish.actualCost > 0 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("圆满实付")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        Text(FormatUtils.formattedYuan(cents: wish.actualCost, includeSymbol: true))
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading, weight: .bold))
                            .foregroundStyle(ArchivePalette.accentMoss)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("意向预算")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        Text(FormatUtils.formattedYuan(cents: wish.budget, includeSymbol: true))
                            .font(ArchiveTypography.monoScale(size: 12.5, weight: .semibold))
                            .foregroundStyle(wish.budget > 0 ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    if wish.status != "fulfilled" {
                        Button(action: onResolve) {
                            HStack(spacing: ArchiveSpacing.xs) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("圆满心愿")
                                    .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(ArchivePalette.accentMoss)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(ArchivePalette.accentMoss.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.accentMoss.opacity(0.3), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                            Text("已归册")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                        }
                        .foregroundStyle(ArchivePalette.accentMoss)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(ArchivePalette.accentMoss.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    }

                    HStack(spacing: 6) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(6)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                .overlay(
                                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                )
                                .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                        }
                        .buttonStyle(.plain)
                        .focused($focusedAction, equals: .edit)
                        .paperFocusRing(isFocused: focusedAction == .edit, cornerRadius: ArchiveRadius.xs)
                        .help("修订心愿")
                        .accessibilityLabel("修订心愿")

                        Button(action: onDelete) {
                            Image(systemName: ArchiveIcon.delete.systemName)
                                .font(.system(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(6)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                .overlay(
                                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                )
                                .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                        }
                        .buttonStyle(.plain)
                        .focused($focusedAction, equals: .delete)
                        .paperFocusRing(isFocused: focusedAction == .delete, cornerRadius: ArchiveRadius.xs)
                        .help("删除心愿")
                        .accessibilityLabel("删除心愿")
                    }
                    .opacity(isHovering || focusedAction != nil ? 1.0 : 0.4)
                    .animation(nil, value: isHovering)
                }
            }
        }
        .padding(ArchiveCardMetrics.padding)
        .frame(minHeight: 150)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    isHighlighted ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle,
                    lineWidth: isHighlighted ? 1.5 : 0.6
                )
        )
        .paperHover()
        .onHover { isHovering = $0 }
        .contextMenu {
            if wish.status != "fulfilled" {
                Button(action: onResolve) {
                    Label("圆满心愿", systemImage: "sparkles")
                }
            }
            Button(action: onEdit) {
                Label("修订心愿", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("删除心愿", systemImage: "trash")
            }
            Divider()
            Button {
                SecureClipboard.copy(wish.title)
            } label: {
                Label("拷贝心愿名称", systemImage: "doc.on.doc")
            }
            if let note = wish.note, !note.isEmpty {
                Button {
                    SecureClipboard.copy(note)
                } label: {
                    Label("拷贝手记备注", systemImage: "text.quote")
                }
            }
        }
    }

    private var kindIcon: String {
        switch wish.kind {
        case "travel": return "airplane"
        case "milestone": return "flag.fill"
        default: return "bag.fill"
        }
    }

    private var kindTitle: String {
        switch wish.kind {
        case "travel": return "远方旅程"
        case "milestone": return "阶段里程碑"
        default: return "心仪好物"
        }
    }

    private var kindColor: Color {
        switch wish.kind {
        case "travel": return ArchivePalette.categoryColor(for: "交通")
        case "milestone": return ArchivePalette.accentMoss
        default: return ArchivePalette.accentWarm
        }
    }

    private var statusTitle: String {
        switch wish.status {
        case "fulfilled": return "已圆满归册"
        case "relinquished": return "已理性拔草"
        case "shelved": return "暂且搁置"
        default: return "静候圆梦"
        }
    }

    private var statusDotColor: Color {
        switch wish.status {
        case "fulfilled": return ArchivePalette.accentMoss
        case "relinquished": return ArchivePalette.inkMuted
        case "shelved": return ArchivePalette.accentWarm.opacity(0.75)
        default: return ArchivePalette.accentWarm
        }
    }

    private var statusTextColor: Color {
        switch wish.status {
        case "fulfilled": return ArchivePalette.accentMoss
        case "relinquished": return ArchivePalette.inkMuted
        default: return ArchivePalette.inkSecondary
        }
    }

    private var statusBgColor: Color {
        switch wish.status {
        case "fulfilled": return ArchivePalette.accentMoss.opacity(0.10)
        case "relinquished": return ArchivePalette.borderSubtle
        default: return ArchivePalette.archivePaper
        }
    }
}

/// 统一样式与等高对齐的造物项目卡片 (ProjectCardView)
struct ProjectCardView: View {
    let proj: Project
    var isHighlighted: Bool = false
    private enum CardAction: Hashable {
        case edit, delete
    }

    @State private var isHovering: Bool = false
    @FocusState private var focusedAction: CardAction?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶栏：分类标签 + 私密徽标 + 状态标签
            HStack(spacing: 6) {
                if let cat = proj.category, !cat.isEmpty {
                    Text(cat)
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ArchivePalette.accentWarm.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                if proj.isPrivate == true {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text("私密")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    }
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .accessibilityLabel("私密项目")
                }

                Spacer()
                if let status = proj.status, !status.isEmpty {
                    Text(ProjectStatus.normalize(status).displayName)
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.accentMoss)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ArchivePalette.accentMoss.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }
            }
            .padding(.bottom, 8)

            Text(proj.title)
                .font(ArchiveTypography.editorialSerif(size: 16.5, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)

            if let sub = proj.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .padding(.top, 3)
                    .lineLimit(1)
            }

            if !proj.description.isEmpty {
                EditorialProseTextView(
                    proj.description,
                    font: ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body),
                    color: ArchivePalette.inkSecondary,
                    lineSpacing: 2,
                    lineLimit: 3
                )
                .padding(.top, 4)
            }

            Spacer(minLength: 12)

            // 关键：分隔线常驻占据恒定 18.5pt 几何高度，仅用 opacity 切换显隐，彻底消除悬停卡片高度抖动
            Rectangle()
                .fill(ArchivePalette.borderDivider)
                .frame(height: 0.5)
                .padding(.vertical, 9)
                .opacity(isHovering || focusedAction != nil || proj.githubUrl?.isEmpty == false ? 1 : 0.45)

            HStack {
                if let gh = proj.githubUrl, !gh.isEmpty, let url = URL(string: gh) {
                    Link(destination: url) {
                        HStack(spacing: ArchiveSpacing.xs) {
                            Image(systemName: "arrow.up.right.square")
                            Text("源码仓库")
                        }
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    }
                    .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                } else {
                    Spacer(minLength: 0)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                            .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedAction, equals: .edit)
                    .paperFocusRing(isFocused: focusedAction == .edit, cornerRadius: ArchiveRadius.xs)
                    .help("修订项目")
                    .accessibilityLabel("修订项目")

                    Button(action: onDelete) {
                        Image(systemName: ArchiveIcon.delete.systemName)
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                            .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedAction, equals: .delete)
                    .paperFocusRing(isFocused: focusedAction == .delete, cornerRadius: ArchiveRadius.xs)
                    .help("删除项目")
                    .accessibilityLabel("删除项目")
                }
                .opacity(isHovering || focusedAction != nil ? 1.0 : 0.4)
                .animation(nil, value: isHovering)
            }
        }
        .padding(ArchiveCardMetrics.padding)
        .frame(minHeight: 118)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    isHighlighted ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle,
                    lineWidth: isHighlighted ? 1.5 : 0.6
                )
        )
        .paperHover()
        .onHover { isHovering = $0 }
        .contextMenu {
            if let gh = proj.githubUrl, !gh.isEmpty, let url = URL(string: gh) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("打开源码仓库", systemImage: "arrow.up.right.square")
                }
            }
            Button(action: onEdit) {
                Label("修订造物项目", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("删除造物项目", systemImage: "trash")
            }
            Divider()
            Button {
                SecureClipboard.copy(proj.title)
            } label: {
                Label("拷贝项目名称", systemImage: "doc.on.doc")
            }
            if !proj.description.isEmpty {
                Button {
                    SecureClipboard.copy(proj.description)
                } label: {
                    Label("拷贝项目手记", systemImage: "text.quote")
                }
            }
        }
    }
}
