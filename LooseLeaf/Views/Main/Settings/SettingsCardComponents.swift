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
        VStack(alignment: .leading, spacing: 6) {
            if let title = title {
                HStack {
                    Text(title)
                        .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Spacer()
                    if let caption = caption {
                        Text(caption)
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
                .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(ArchivePalette.archiveSubtle.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ArchivePalette.borderSubtle.opacity(0.7), lineWidth: 0.5)
            )

            if let footer = footer {
                Text(footer)
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
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
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(ArchiveTypography.bodySans(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }

            Spacer(minLength: 16)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    /// 卡片内部分隔线（左侧留出图标槽位）
    var settingsRowDivider: some View {
        Divider()
            .padding(.leading, 54)
            .overlay(ArchivePalette.borderSubtle.opacity(0.5))
    }
}
