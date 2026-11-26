// PaperButtons.swift
// 纸本按钮与交互反馈组件 (Pill Button / Hover / Primary Style / Focus Ring)

import SwiftUI

/// 纸签胶囊按钮 (用于分类切换、标签选择，排版杂志风格微高亮)
public struct PaperPillButton: View {
    public let title: String
    public var icon: String?
    public var leadingDotColor: Color?
    public var accentColor: Color?
    public let isSelected: Bool
    public var isCompact: Bool = false
    public let action: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(
        title: String,
        icon: String? = nil,
        leadingDotColor: Color? = nil,
        accentColor: Color? = nil,
        isSelected: Bool,
        isCompact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.leadingDotColor = leadingDotColor
        self.accentColor = accentColor
        self.isSelected = isSelected
        self.isCompact = isCompact
        self.action = action
    }

    public var body: some View {
        let resolvedAccent = accentColor ?? ArchivePalette.accentWarm
        Button(action: action) {
            HStack(spacing: isCompact ? 4 : 5) {
                if let leadingDotColor {
                    Circle()
                        .fill(leadingDotColor)
                        .frame(width: 5.5, height: 5.5)
                        .accessibilityHidden(true)
                }
                if let icon {
                    Image(systemName: icon)
                        .font(ArchiveTypography.icon(size: isCompact ? ArchiveTypography.Scale.badge : ArchiveTypography.Scale.label, weight: isSelected ? .semibold : .medium))
                        .imageScale(.small)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            isSelected
                                ? resolvedAccent
                                : (accentColor ?? ArchivePalette.inkSecondary)
                        )
                }
                Text(title)
                    .font(ArchiveTypography.bodySans(size: isCompact ? 11 : 11.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isSelected ? resolvedAccent : ArchivePalette.inkSecondary)
            .padding(.horizontal, isCompact ? 8 : 10)
            .padding(.vertical, isCompact ? 3.5 : 5)
            .frame(minHeight: ArchiveHitTarget.minPointer)
            .background(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .fill(isSelected ? resolvedAccent.opacity(0.12) : ArchivePalette.archiveSubtle.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .stroke(isSelected ? resolvedAccent.opacity(0.35) : Color.clear, lineWidth: 0.5)
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

/// 散页原生分类胶囊选择条（日常 / 摄影 / 旅途 / 静物 / 影像）
/// 统一供菜单栏极速捕捉、主窗口新建散页模态与编辑手稿弹窗复用。
public struct EntryCategoryPickerRow: View {
    @Binding public var selection: EntryCategory
    public var label: String?
    public var isCompact: Bool

    public init(
        selection: Binding<EntryCategory>,
        label: String? = nil,
        isCompact: Bool = false
    ) {
        self._selection = selection
        self.label = label
        self.isCompact = isCompact
    }

    public var body: some View {
        HStack(spacing: ArchiveSpacing.s) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.footnote))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isCompact ? ArchiveSpacing.xs : 6) {
                    ForEach(EntryCategory.allCases) { category in
                        PaperPillButton(
                            title: category.label,
                            icon: category.symbolName,
                            accentColor: category.accentColor,
                            isSelected: selection == category,
                            isCompact: isCompact
                        ) {
                            selection = category
                        }
                    }
                }
            }
        }
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
