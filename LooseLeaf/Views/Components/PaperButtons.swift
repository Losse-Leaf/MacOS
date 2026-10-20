// PaperButtons.swift
// 纸本按钮与交互反馈组件 (Pill Button / Hover / Primary Style / Focus Ring)
// 职责：胶囊标签按钮、悬停高亮修饰符、主按钮样式与键盘焦点环，
//       均为可复用的按钮外观与指针/键盘反馈基元。
// 来源：由 Views/Components/PaperComponents.swift 按职责拆分而来，代码逻辑保持原样。

import SwiftUI

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
            // 命中区下限：胶囊视觉不变，纵向至少留出指针可点高度
            .frame(minHeight: ArchiveHitTarget.minPointer)
            .background(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .fill(isSelected ? ArchivePalette.accentWarm.opacity(0.12) : ArchivePalette.archiveSubtle.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .stroke(isSelected ? ArchivePalette.accentWarm.opacity(0.35) : Color.clear, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// 纸面悬停高亮修饰符：轻微提亮 + 描边加深（为 macOS 指针交互提供物理反馈）
public struct PaperHoverModifier: ViewModifier {
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .brightness(isHovering ? 0.015 : 0)
            // 悬停高亮：0.5pt 暖色描边（米白纸面上清晰可辨）
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .stroke(isHovering ? ArchivePalette.accentWarm.opacity(0.45) : Color.clear, lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
            // 抬升：阴影半径 2→6、纵向偏移 1→2
            .shadow(color: Color.black.opacity(isHovering ? 0.05 : 0), radius: isHovering ? 6 : 2, y: isHovering ? 2 : 1)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : ArchiveMotion.quick) {
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
            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
            .foregroundStyle(isProminent ? ArchivePalette.archivePaper : ArchivePalette.inkPrimary)
            .padding(.horizontal, ArchiveSpacing.m)
            .padding(.vertical, 6)
            // 命中区下限：按钮内容纵向至少留出指针可点高度
            .frame(minHeight: ArchiveHitTarget.minPointer)
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

// MARK: - 纸本焦点环 (Keyboard Focus Ring)

/// 自绘焦点环：纸墨主题下系统默认焦点环在自定义按钮上几乎不可见，
/// 统一以暖色描边表达键盘焦点位置。
struct PaperFocusRingModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(isFocused ? ArchivePalette.accentWarm : Color.clear, lineWidth: 1.5)
                .allowsHitTesting(false)
        )
    }
}

public extension View {
    /// 纸本焦点环（键盘导航时显形）
    func paperFocusRing(isFocused: Bool, cornerRadius: CGFloat = ArchiveRadius.xs) -> some View {
        modifier(PaperFocusRingModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}
