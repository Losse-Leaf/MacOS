import SwiftUI

// 原「造物 / 心愿 / 行迹」聚合主视图已拆分为 WishlistView / ProjectsView / TravelAtlasView，
// 本文件只保留多端共用的卡片、状态语义字典与抽屉载荷类型；
// 其余编辑 Sheet 与星野画布已按职责下沉至同目录的 ProjectsWishes/ 子目录。

// MARK: - 造物项目状态语义 (Project Status)

/// 造物项目状态语义字典（全应用唯一真源）。
/// 新建 / 修订项目与 `ProjectsView` 的状态筛选共用同一套取值，
/// 避免「默认写入的状态」与「筛选匹配的状态」不一致导致项目在筛选下消失。
enum ProjectStatus: String, CaseIterable, Identifiable {
    /// 进行中
    case active = "Active"
    /// 已归档
    case archived = "Archived"
    /// 持续维护（兼容旧数据的表述，语义上等同于进行中）
    case ongoing = "持续维护"

    var id: String { rawValue }

    /// 面向用户的中文展示名
    var displayName: String {
        switch self {
        case .active: return "进行中"
        case .archived: return "已归档"
        case .ongoing: return "持续维护"
        }
    }

    /// 是否属于「进行中」语义（含旧数据表述 active / 持续维护 等大小写变体）
    var isActiveLike: Bool {
        switch self {
        case .active, .ongoing: return true
        case .archived: return false
        }
    }

    /// 将任意来源的状态字符串归一化为语义枚举（无法识别时按进行中处理）
    static func normalize(_ raw: String?) -> ProjectStatus {
        guard let raw, !raw.isEmpty else { return .active }
        if let matched = ProjectStatus(rawValue: raw) {
            return matched
        }
        // 兼容后端可能返回的小写形式（如 active / archived）
        let lowered = raw.lowercased()
        if lowered == ProjectStatus.archived.rawValue.lowercased() { return .archived }
        return .active
    }

    /// 判断给定状态是否命中指定筛选值（`all` 表示不限）
    static func matches(_ raw: String?, selected: String) -> Bool {
        if selected == "all" { return true }
        let normalized = normalize(raw)
        if selected == ProjectStatus.active.rawValue {
            return normalized.isActiveLike
        }
        if selected == ProjectStatus.archived.rawValue {
            return normalized == .archived
        }
        return false
    }
}

/// 城市 / 省份回忆抽屉的选择载荷（TravelAtlasView 与抽屉 Sheet 共用）
struct DrawerCitySelection: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let name: String
}

struct DrawerProvinceSelection: Identifiable, Equatable {
    var id: String { adcode }
    let adcode: String
    let name: String
}

/// 统一样式与等高对齐的心愿典藏卡片 (WishCardView)
struct WishCardView: View {
    let wish: Wish
    let onResolve: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// 悬停态：次级动作（修订 / 删除）只在悬停时出现
    @State private var isHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 顶栏：分类标签徽章 + 状态微胶囊
            HStack(alignment: .center) {
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

            // 3. 规格
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

            // 4. 手记备注
            if let note = wish.note, !note.isEmpty {
                Text(LocalizedStringKey(note))
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.inkSecondary.opacity(0.88))
                    .lineLimit(2)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }

            // 弹性占位：将底部预算与操作栏统一牢牢推向卡片底端，确保各卡片严格等高对齐
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

                // 主理人操作区
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

                    // 次级动作（修订 / 删除）改为**悬停才出现** ——
                    // 与时间流卡片一致：一排卡片里常驻一堆图标按钮，视觉噪音很大。
                    // 主操作「圆满心愿」保持常驻，它是被扫到的主要动作。
                    if isHovering {
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
                                // 命中区下限：图标视觉保持 11pt，可点区域不小于 28pt
                                .frame(minWidth: ArchiveHitTarget.minPointer, minHeight: ArchiveHitTarget.minPointer)
                        }
                        .buttonStyle(.plain)
                        .help("修订心愿")
                        .accessibilityLabel("修订心愿")

                        Button(action: onDelete) {
                            Image(systemName: ArchiveIcon.delete.systemName)
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
                        .help("删除心愿")
                        .accessibilityLabel("删除心愿")
                    }
                }
            }
        }
        .padding(ArchiveCardMetrics.padding)
        // 关键：原先是 195 —— 心愿内容通常只有「标题 + 一句手记」，
        // 底部又被 Spacer 推到底，于是中间空出一大片，比时间流的卡片还空。
        // 收到 168 之后，卡片紧贴内容，底部预算栏不再悬在半空。
        .frame(minHeight: 150)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.6)
        )
        // 原先这里有一层 radius 6 的模糊阴影：SwiftUI 的 `.shadow` 会对整棵子树做离屏渲染，
        // 实测单张心愿/造物卡 22~27ms —— 列表里放 20 张就是半秒以上的滚动卡顿。
        // 该卡片已有 0.6pt 描边承担层级，去掉阴影后视觉几乎无差别。
        .paperHover()
        .onHover { isHovering = $0 }
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
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶栏：分类标签 + 状态标签
            HStack {
                if let cat = proj.category, !cat.isEmpty {
                    Text(cat)
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ArchivePalette.accentWarm.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }
                Spacer()
                if let status = proj.status, !status.isEmpty {
                    // 语义化展示：已知状态给出中文名，未知取值按「进行中」语义归一化
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
                Text(LocalizedStringKey(proj.description))
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .lineLimit(3)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }

            Spacer(minLength: 12)

            Rectangle()
                .fill(ArchivePalette.borderDivider)
                .frame(height: 0.5)
                .padding(.vertical, 9)

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
                    .help("修订项目")
                    .accessibilityLabel("修订项目")

                    Button(action: onDelete) {
                        Image(systemName: ArchiveIcon.delete.systemName)
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
                    .help("删除项目")
                    .accessibilityLabel("删除项目")
                }
            }
        }
        .padding(ArchiveCardMetrics.padding)
        .frame(minHeight: 195)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.6)
        )
        // 原先这里有一层 radius 6 的模糊阴影：SwiftUI 的 `.shadow` 会对整棵子树做离屏渲染，
        // 实测单张心愿/造物卡 22~27ms —— 列表里放 20 张就是半秒以上的滚动卡顿。
        // 该卡片已有 0.6pt 描边承担层级，去掉阴影后视觉几乎无差别。
        .paperHover()
    }
}

// MARK: - 预览 (Preview)

#Preview("心愿典藏卡片") {
    WishCardView(
        wish: ArchivePreviewFixtures.wishes()[0],
        onResolve: {},
        onEdit: {},
        onDelete: {}
    )
    .frame(width: 360)
    .padding(ArchiveSpacing.l)
}

#Preview("造物项目卡片") {
    ProjectCardView(
        proj: ArchivePreviewFixtures.projects()[0],
        onEdit: {},
        onDelete: {}
    )
    .frame(width: 360)
    .padding(ArchiveSpacing.l)
}
