import SwiftUI

/// 配置类视图共用的 Grouped 卡片容器（供 Settings/ 下五个 tab 复用）
extension View {
    /// 拟物 macOS 风格分组卡片：标题 + 说明 + 内容 + 脚注
    func settingsCardSection<Content: View>(
        title: String? = nil,
        caption: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
            if let title = title {
                HStack {
                    Text(title)
                        .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Spacer()
                    if let caption = caption {
                        Text(caption)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
                .padding(.horizontal, ArchiveSpacing.xs)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(ArchivePalette.archiveSubtle.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: ArchiveCardMetrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveCardMetrics.radius)
                    .stroke(ArchivePalette.borderSubtle.opacity(0.7), lineWidth: 0.5)
            )

            if let footer = footer {
                Text(footer)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .padding(.horizontal, ArchiveSpacing.s)
                    .padding(.top, ArchiveSpacing.xxs)
            }
        }
    }

    /// 卡片内单行：图标 + 标题/副标题 + 右侧尾部控件
    func settingsCardRow<Trailing: View>(
        icon: String,
        iconColor: Color = ArchivePalette.accentWarm,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: ArchiveSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: ArchiveHitTarget.minPointer, height: ArchiveHitTarget.minPointer)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .imageScale(.medium)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                Text(title)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }

            Spacer(minLength: ArchiveSpacing.l)

            trailing()
        }
        .padding(.horizontal, ArchiveCardMetrics.padding)
        .padding(.vertical, 11)
    }

    /// 卡片内部分隔线（左侧留出图标槽位）
    var settingsRowDivider: some View {
        Divider()
            .padding(.leading, ArchiveSpacing.xl + ArchiveSpacing.m)
            .overlay(ArchivePalette.borderSubtle.opacity(0.5))
    }
}

// MARK: - 设置页统一操作反馈条

/// 设置页统一操作反馈条：错误（朱砂）优先、成功（苔绿）其次，同位互斥展示。
/// 全局函数（非 View 扩展方法），便于在任意 `body` 内作为独立节点插入。
public func settingsFeedbackBanner(feedback: String?, error: String?) -> some View {
    Group {
        if let error, !error.isEmpty {
            feedbackRow(text: error, icon: "exclamationmark.octagon.fill", tint: ArchivePalette.accentWarm)
        } else if let feedback, !feedback.isEmpty {
            feedbackRow(text: feedback, icon: "checkmark.seal.fill", tint: ArchivePalette.accentMoss)
        }
    }
    .accessibilityElement(children: .combine)
}

/// 反馈条内部单行：图标 + 文案
private func feedbackRow(text: String, icon: String, tint: Color) -> some View {
    HStack(spacing: ArchiveSpacing.s) {
        Image(systemName: icon)
            .font(.system(size: 12))
            .accessibilityHidden(true)
        Text(text)
            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
            .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, ArchiveSpacing.m)
    .padding(.vertical, ArchiveSpacing.s)
    .background(tint.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
    .overlay(
        RoundedRectangle(cornerRadius: ArchiveRadius.sm)
            .stroke(tint.opacity(0.4), lineWidth: 0.5)
    )
}
