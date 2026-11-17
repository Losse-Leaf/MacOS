import SwiftUI

/// 纸本确认与警示对话框 (PaperConfirmDialogView)
public struct PaperConfirmDialogView: View {
    let request: ConfirmDialogRequest
    var onDismiss: () -> Void

    @State private var isHoveringCancel: Bool = false
    @State private var isHoveringConfirm: Bool = false
    @FocusState private var focusedAction: FocusAction?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum FocusAction: Hashable {
        case cancel
        case confirm
    }

    public init(request: ConfirmDialogRequest, onDismiss: @escaping () -> Void) {
        self.request = request
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Group {
                if reduceTransparency {
                    Color.black.opacity(0.62)
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.32))
                }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                cancelAction()
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    if request.danger {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .accessibilityHidden(true)
                    }

                    Text(request.title)
                        .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Spacer()

                    PaperIconButton(
                        systemName: ArchiveIcon.close.systemName,
                        label: "关闭确认对话框",
                        help: "取消关闭 (Esc)",
                        size: 11,
                        tint: ArchivePalette.inkMuted,
                        action: cancelAction
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                Divider()
                    .overlay(ArchivePalette.borderSubtle.opacity(0.8))

                Text(request.message)
                    .font(ArchiveTypography.editorialSerif(size: 13.5, weight: request.danger ? .medium : .regular))
                    .foregroundStyle(request.danger ? ArchivePalette.accentWarm : ArchivePalette.inkSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                HStack(spacing: 10) {
                    Spacer()

                    Button {
                        cancelAction()
                    } label: {
                        Text(request.cancelText)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(isHoveringCancel ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(minHeight: ArchiveHitTarget.minPointer)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringCancel = $0 }
                    .focused($focusedAction, equals: .cancel)
                    .paperFocusRing(isFocused: focusedAction == .cancel, cornerRadius: ArchiveRadius.xs)
                    .accessibilityLabel(request.cancelText)
                    .accessibilityHint("按 Esc 键亦可取消")

                    Button {
                        confirmAction()
                    } label: {
                        Text(request.confirmText)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body, weight: .medium))
                            .foregroundStyle(ArchivePalette.archivePaper)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6.5)
                            .frame(minHeight: ArchiveHitTarget.minPointer)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(request.danger ? ArchivePalette.accentWarm : ArchivePalette.inkPrimary)
                            )
                            .opacity(isHoveringConfirm ? 0.9 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringConfirm = $0 }
                    .focused($focusedAction, equals: .confirm)
                    .paperFocusRing(isFocused: focusedAction == .confirm, cornerRadius: 3.5)
                    .accessibilityLabel(request.confirmText)
                    .accessibilityHint("按回车键确认")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(width: 390)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
            .shadow(color: Color.black.opacity(0.35), radius: 28, x: 0, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.md)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 1)
            )
            .onTapGesture {}
            .accessibilityElement(children: .contain)
            .accessibilityLabel(request.title)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    )
            )
        }
        .onAppear {
            focusedAction = request.danger ? .cancel : .confirm
        }
        .onKeyPress(.escape) {
            cancelAction()
            return .handled
        }
        .onKeyPress(.tab) {
            focusedAction = (focusedAction == .cancel) ? .confirm : .cancel
            return .handled
        }
        .onKeyPress(.return) {
            if focusedAction != nil {
                return .ignored
            }
            if request.danger {
                cancelAction()
            } else {
                confirmAction()
            }
            return .handled
        }
    }

    private func cancelAction() {
        request.onCancel?()
        onDismiss()
    }

    private func confirmAction() {
        if AppState.shared.enablesHapticFeedback {
            ArchiveFeedback.light()
        }
        request.onConfirm()
        onDismiss()
    }
}
