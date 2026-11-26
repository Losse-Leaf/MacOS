import SwiftUI
import AppKit

// MARK: - 统一图标按钮 (Paper Icon Button)

public struct PaperIconButton: View {
    private let systemName: String
    private let label: String
    private let help: String?
    private let size: CGFloat
    private let tint: Color?
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

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
                .font(ArchiveTypography.icon(size: size))
                .foregroundStyle(tint ?? ArchivePalette.inkSecondary)
                .frame(width: ArchiveHitTarget.minPointer, height: ArchiveHitTarget.minPointer)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1.0 : 0.42)
        }
        .buttonStyle(.plain)
        .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}

// MARK: - 统一空状态 (Empty State)

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
                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.emptyIcon, weight: .light))
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
            ForEach(0..<max(1, rowCount), id: \.self) { _ in
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

public struct PaperSheetScaffold<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let width: CGFloat
    private let maxBodyHeight: CGFloat
    private let isSubmitting: Bool
    private let isSubmitDisabled: Bool
    private let submitTitle: String
    private let onCancel: () -> Void
    private let onSubmit: () -> Void
    private let content: () -> Content

    public init(
        title: String,
        subtitle: String? = nil,
        width: CGFloat = ArchiveSheetWidth.standard,
        maxBodyHeight: CGFloat = 520,
        isSubmitting: Bool = false,
        isSubmitDisabled: Bool = false,
        submitTitle: String = "保存",
        onCancel: @escaping () -> Void,
        onSubmit: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.maxBodyHeight = maxBodyHeight
        self.isSubmitting = isSubmitting
        self.isSubmitDisabled = isSubmitDisabled
        self.submitTitle = submitTitle
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.cardTitle, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            ScrollView(.vertical) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maxBodyHeight)

            Divider().overlay(ArchivePalette.borderSubtle)

            HStack {
                Button("取消", action: onCancel)
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    onSubmit()
                } label: {
                    ZStack {
                        Text(submitTitle)
                            .opacity(isSubmitting ? 0 : 1)
                        ProgressView()
                            .controlSize(.small)
                            .opacity(isSubmitting ? 1 : 0)
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
                .disabled(isSubmitting || isSubmitDisabled)
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

public struct PaperModalOverlay<Content: View>: View {
    private let onDismiss: () -> Void
    private let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(onDismiss: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.onDismiss = onDismiss
        self.content = content
    }

    public var body: some View {
        ZStack {
            Group {
                if reduceTransparency {
                    Color.black.opacity(0.62)
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.28))
                }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .accessibilityHidden(true)

            content()
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.lg))
                .shadow(color: Color.black.opacity(0.28), radius: 28, x: 0, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.lg)
                        .stroke(ArchivePalette.borderSubtle.opacity(0.8), lineWidth: 0.8)
                )
                .onTapGesture {}
        }
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal: .scale(scale: 0.96).combined(with: .opacity)
                )
        )
    }
}
