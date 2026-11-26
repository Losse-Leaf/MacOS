import SwiftUI
import AppKit

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
                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.micro))
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
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.miniBadge))
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
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.cardTitle, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)

            // 3. 规格参数
            if let spec = wish.spec, !spec.isEmpty {
                HStack(spacing: ArchiveSpacing.xs) {
                    Image(systemName: "slider.horizontal.2")
                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.micro))
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
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.mediumBody, weight: .semibold))
                            .foregroundStyle(wish.budget > 0 ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    if wish.status != "fulfilled" {
                        Button(action: onResolve) {
                            HStack(spacing: ArchiveSpacing.xs) {
                                Image(systemName: "sparkles")
                                    .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.micro))
                                Text("圆满心愿")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.footnote, weight: .medium))
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
                                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.micro))
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
                                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.caption))
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
                                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.caption))
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
        .padding(ArchiveSpacing.l)
        .frame(minHeight: 150)
        .background(ArchivePalette.archiveSubtle.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.md)
                .stroke(
                    isHighlighted ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle.opacity(0.65),
                    lineWidth: isHighlighted ? 1.5 : 0.5
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
