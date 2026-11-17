// PaperButtons.swift
// 纸本按钮与交互反馈组件 (Pill Button / Hover / Primary Style / Focus Ring)

import SwiftUI

/// 纸签胶囊按钮 (用于分类切换、标签选择，排版杂志风格微高亮)
public struct PaperPillButton: View {
    public let title: String
    public var icon: String?
    public let isSelected: Bool
    public var isCompact: Bool = false
    public let action: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(
        title: String,
        icon: String? = nil,
        isSelected: Bool,
        isCompact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.isCompact = isCompact
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: isCompact ? 4 : 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: isCompact ? 9.5 : 10.5, weight: isSelected ? .semibold : .medium))
                        .imageScale(.small)
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title)
                    .font(ArchiveTypography.bodySans(size: isCompact ? 11 : 11.5, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? ArchivePalette.accentWarm : ArchivePalette.inkSecondary)
            .padding(.horizontal, isCompact ? 8 : 10)
            .padding(.vertical, isCompact ? 3.5 : 5)
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
            .opacity(isEnabled ? 1.0 : 0.42)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .paperFocusRing(isFocused: isFocused, cornerRadius: ArchiveRadius.sm)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }
}

/// 纸面悬停高亮修饰符
public struct PaperHoverModifier: ViewModifier {
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .brightness(isHovering ? 0.015 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .stroke(
                        isHovering ? ArchivePalette.accentWarm.opacity(0.55) : Color.clear,
                        lineWidth: isHovering ? 1.0 : 0.5
                    )
                    .allowsHitTesting(false)
            )
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : ArchiveMotion.quick) {
                    isHovering = hovering
                }
            }
    }
}

public extension View {
    @ViewBuilder
    func paperHover(enabled: Bool = true) -> some View {
        if enabled {
            modifier(PaperHoverModifier())
        } else {
            self
        }
    }

    func paperButtonFocusRing(cornerRadius: CGFloat = ArchiveRadius.sm) -> some View {
        modifier(PaperButtonFocusRingModifier(cornerRadius: cornerRadius))
    }
}

struct PaperButtonFocusRingModifier: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .paperFocusRing(isFocused: isFocused, cornerRadius: cornerRadius)
    }
}

/// 出版物操作按钮样式（完整支持 `@Environment(\.isEnabled)` 禁用态视觉降级）
public struct PaperPrimaryButtonStyle: ButtonStyle {
    public var isProminent: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(isProminent: Bool = true) {
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = isEnabled && configuration.isPressed
        return configuration.label
            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
            .foregroundStyle(isProminent ? ArchivePalette.archivePaper : ArchivePalette.inkPrimary)
            .padding(.horizontal, ArchiveSpacing.m)
            .padding(.vertical, 6)
            .frame(minHeight: ArchiveHitTarget.minPointer)
            .background(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .fill(isProminent ? ArchivePalette.inkPrimary : ArchivePalette.archivePaper)
                    .opacity(pressed ? 0.84 : 1.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .stroke(isProminent ? Color.clear : ArchivePalette.borderSubtle, lineWidth: 0.5)
            )
            .paperElevation(isProminent && isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1.0 : 0.42)
    }
}

// MARK: - 纸本焦点环 (Keyboard Focus Ring)

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
    func paperFocusRing(isFocused: Bool, cornerRadius: CGFloat = ArchiveRadius.xs) -> some View {
        modifier(PaperFocusRingModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}
