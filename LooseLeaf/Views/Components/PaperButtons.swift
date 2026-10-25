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
    /// 紧凑模式：用于「一整排」类目筛选这类密集场景
    ///
    /// 关键：资产页有 16 个类目胶囊横排一行，默认尺寸下它们读起来像一堵墙
    /// （而且右端被裁掉）。紧凑版把字号与内边距各收一档，
    /// 一行能多放几个，也不再喧宾夺主。
    public var isCompact: Bool = false
    public let action: () -> Void

    /// 键盘焦点态（用于画纸本焦点环）
    @FocusState private var isFocused: Bool

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
        // 关键（MC-06）：键盘焦点环。
        // 系统默认焦点环在自定义按钮上几乎不可见，而胶囊按钮是本应用
        // **最常被键盘 Tab 到的控件**（类目筛选、类型切换、渠道选择…）——
        // 没有焦点指示，键盘用户根本不知道自己在哪儿。
        .focused($isFocused)
        .paperFocusRing(isFocused: isFocused, cornerRadius: ArchiveRadius.sm)
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
            // 抬升：早期版本用 `.shadow(radius: 2→6)` 表达，但 SwiftUI 的 `.shadow`
            // 会对整棵子树做离屏渲染 —— 即使不悬停（透明度为 0）该修饰符依然生效，
            // 于是时间流里每一张卡片都要额外付一次离屏渲染。
            // 改为**描边加粗 + 提亮**来表达抬升：零离屏渲染，悬停反馈依旧清晰。
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
    /// 纸面悬停反馈（卡片 / 缩略图等可交互面板）
    func paperHover() -> some View {
        modifier(PaperHoverModifier())
    }

    /// 按钮的纸本焦点环（键盘导航时显形）
    ///
    /// 关键（MC-06）：`ButtonStyle` 的 `makeBody` **拿不到焦点状态**
    /// （`@FocusState` 必须是 View 成员，`ButtonStyle.Configuration` 也不公开 `trigger`），
    /// 所以焦点环只能挂在 **Button 本身**上 —— 与 `PaperPillButton` / `PaperSelect`
    /// 完全同一套写法。
    ///
    /// 为什么不把主按钮改造成 View 组件（那才是「正规」做法）：
    /// 96 处调用里 **39 处**是 `Button { } label: { }` 的自定义标签形态，
    /// 改造成组件就得把标签搬进组件里 —— 逐处搬运等于逐处重写，
    /// 而这个修饰符**一行加在 `.buttonStyle` 之后**即可：
    /// Button 的标签、动作、以及 `.keyboardShortcut` / `.disabled` 等修饰符**全都不动**。
    func paperButtonFocusRing(cornerRadius: CGFloat = ArchiveRadius.sm) -> some View {
        modifier(PaperButtonFocusRingModifier(cornerRadius: cornerRadius))
    }
}

/// 按钮焦点环修饰符：自持 `@FocusState`，把焦点位置画成暖色描边
struct PaperButtonFocusRingModifier: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .paperFocusRing(isFocused: isFocused, cornerRadius: cornerRadius)
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
