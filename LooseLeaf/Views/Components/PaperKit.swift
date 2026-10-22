import SwiftUI
import AppKit

// MARK: - 动效与减弱动态效果 (Reduce Motion Support)

/// 全应用统一的「减弱动态效果」开关封装。
/// macOS「系统设置 → 辅助功能 → 显示 → 减弱动态效果」开启后，所有非必要动效必须停止。
public enum ArchiveMotionGate {
    /// 依据系统偏好决定是否执行动画
    public static func perform(_ reduceMotion: Bool, _ base: Animation, _ action: () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(base, action)
        }
    }
}

public struct ArchiveReduceMotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    public func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

public extension View {
    /// 附加一段动效；当用户开启「减弱动态效果」时自动失效。
    func archiveAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ArchiveReduceMotionModifier(animation: animation, value: value))
    }

    /// 依据系统偏好执行动画的便捷方法（用于 `withAnimation` 场景）
    func archiveAnimating<V: Equatable>(
        _ animation: Animation,
        value: V,
        reduceMotion: Bool,
        _ action: @escaping () -> Void
    ) {
        ArchiveMotionGate.perform(reduceMotion, animation, action)
    }
}

// MARK: - 统一图标按钮 (Paper Icon Button)

/// 全应用统一的图标按钮：
/// - 视觉图形保持 11~12pt，但**命中区不小于 `ArchiveHitTarget.minPointer`**
/// - 强制要求 `label`（VoiceOver 朗读），`help` 提供 tooltip
public struct PaperIconButton: View {
    private let systemName: String
    private let label: String
    private let help: String?
    private let size: CGFloat
    private let tint: Color?
    private let action: () -> Void

    public init(
        systemName: String,
        label: String,
        help: String? = nil,
        size: CGFloat = 12,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.label = label
        self.help = help
        self.size = size
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(tint ?? ArchivePalette.inkSecondary)
                .frame(width: ArchiveHitTarget.minPointer, height: ArchiveHitTarget.minPointer)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}

// MARK: - 统一空状态 (Empty State)

/// 统一空状态容器：意象图标 + 标题 + 说明 + 行动召唤按钮
public struct ArchiveEmptyState: View {
    private let systemName: String
    private let title: String
    private let message: String
    private let primaryTitle: String?
    private let primaryAction: (() -> Void)?
    private let secondaryTitle: String?
    private let secondaryAction: (() -> Void)?

    public init(
        systemName: String,
        title: String,
        message: String,
        primaryTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.systemName = systemName
        self.title = title
        self.message = message
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        VStack(spacing: ArchiveSpacing.s) {
            Image(systemName: systemName)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ArchivePalette.inkMuted)
                .accessibilityHidden(true)

            Text(title)
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .medium))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text(message)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if primaryTitle != nil || secondaryTitle != nil {
                HStack(spacing: ArchiveSpacing.s) {
                    if let primaryTitle, let primaryAction {
                        Button(primaryTitle, action: primaryAction)
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                            .paperButtonFocusRing()
                    }
                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle, action: secondaryAction)
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .paperButtonFocusRing()
                    }
                }
                .padding(.top, ArchiveSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(ArchiveSpacing.xl)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }
}

// MARK: - 统一骨架屏 (Skeleton)

/// 首屏加载骨架：与纸本卡片同构的占位条。
/// 关键：加载态与「真的没有记录」必须视觉可区分，否则用户会以为数据丢了。
public struct ArchiveSkeletonView: View {
    private let rowCount: Int
    private let showsHeader: Bool

    public init(rowCount: Int = 4, showsHeader: Bool = true) {
        self.rowCount = rowCount
        self.showsHeader = showsHeader
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            if showsHeader {
                skeletonBar(width: 220, height: 22)
                skeletonBar(width: 140, height: 12)
            }
            ForEach(0..<max(1, rowCount), id: \.self) { index in
                VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                    HStack(spacing: ArchiveSpacing.s) {
                        skeletonBar(width: 64, height: 16)
                        skeletonBar(width: 120, height: 12)
                    }
                    skeletonBar(width: nil, height: 12)
                    skeletonBar(width: 220, height: 12)
                }
                .padding(ArchiveCardMetrics.padding)
                .background(ArchivePalette.archiveSubtle.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: ArchiveCardMetrics.radius))
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载档案")
    }

    private func skeletonBar(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(ArchivePalette.borderSubtle.opacity(0.55))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

// MARK: - 统一 Sheet 骨架 (Sheet Scaffold)

/// 统一表单弹窗骨架：标题 + 内容 + 取消/提交。
/// 消除 12 处逐行重复的 `VStack { TextField…, 取消 + 提交, .padding(20).frame(width:)` 结构。
public struct PaperSheetScaffold<Content: View>: View {
    private let title: String
    private let width: CGFloat
    private let isSubmitting: Bool
    private let submitTitle: String
    private let onCancel: () -> Void
    private let onSubmit: () -> Void
    private let content: () -> Content

    public init(
        title: String,
        width: CGFloat = ArchiveSheetWidth.standard,
        isSubmitting: Bool = false,
        submitTitle: String = "保存",
        onCancel: @escaping () -> Void,
        onSubmit: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.width = width
        self.isSubmitting = isSubmitting
        self.submitTitle = submitTitle
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            Text(title)
                .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Divider().overlay(ArchivePalette.borderSubtle)

            content()

            Divider().overlay(ArchivePalette.borderSubtle)

            HStack {
                Button("取消", action: onCancel)
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                Spacer()
                Button {
                    onSubmit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(submitTitle)
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
                .disabled(isSubmitting)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(ArchiveSpacing.l)
        .frame(minWidth: width * 0.86, idealWidth: width, maxWidth: width)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.lg)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }
}

// MARK: - 统一纸墨模态通道 (Paper Modal)

/// 全应用统一的居中纸墨模态层。
/// 与系统 `.sheet` 的差异：居中卡片 + 半透明遮罩 + 点击遮罩关闭 + ESC 关闭。
public struct PaperModalOverlay<Content: View>: View {
    private let onDismiss: () -> Void
    private let content: () -> Content

    public init(onDismiss: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.onDismiss = onDismiss
        self.content = content
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .accessibilityHidden(true)

            content()
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.lg))
                .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.lg)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 1)
                )
                .onTapGesture { /* 吸收点击，避免冒泡关闭 */ }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)
        ))
    }
}
