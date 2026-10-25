import SwiftUI

/// 纸本确认与警示对话框 (PaperConfirmDialogView)
/// 严格对标 Web ConfirmDialog.vue：
/// - 纯正纸墨基底 (--bg-archive) 与细腻边框 (--border-subtle)
/// - 警示标头 (朱砂 Vermilion 危险态与沉着墨黑)
/// - 键盘回车快捷确认与 Esc 快捷取消
/// - 触控板微震与活页声效反馈
public struct PaperConfirmDialogView: View {
    let request: ConfirmDialogRequest
    var onDismiss: () -> Void

    @State private var isHoveringCancel: Bool = false
    @State private var isHoveringConfirm: Bool = false
    /// 键盘焦点所在按钮（用于绘制纸本焦点环）
    @FocusState private var focusedAction: FocusAction?

    /// 对话框内可获焦点的操作
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
            // 背景半透明磨砂遮罩 (macOS 系统级 Vibrancy Material)
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.32))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelAction()
                }

            // 弹窗本体
            VStack(alignment: .leading, spacing: 0) {
                // 1. 标题栏
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

                    // 统一图标按钮：命中区不小于指针可点下限
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

                // 2. 正文提示词（危险态以朱砂色强调，确保一眼可辨）
                Text(request.message)
                    .font(ArchiveTypography.editorialSerif(size: 13.5, weight: request.danger ? .medium : .regular))
                    .foregroundStyle(request.danger ? ArchivePalette.accentWarm : ArchivePalette.inkSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                // 3. 底部操作栏
                HStack(spacing: 10) {
                    Spacer()

                    // 取消按钮
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

                    // 确认按钮 (主操作)
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
            .onTapGesture {
                // 吸收点击，阻止遮罩冒泡
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(request.title)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.96).combined(with: .opacity),
                removal: .scale(scale: 0.96).combined(with: .opacity)
            ))
        }
        .onKeyPress(.escape) {
            cancelAction()
            return .handled
        }
        .onKeyPress(.return) {
            // 焦点落在按钮上时交由按钮自身处理，避免「确认」被触发两次
            if focusedAction != nil {
                return .ignored
            }
            confirmAction()
            return .handled
        }
    }

    private func cancelAction() {
        request.onCancel?()
        onDismiss()
    }

    private func confirmAction() {
        // 触感确认（用户可在偏好设置中关闭）
        if AppState.shared.enablesHapticFeedback {
            ArchiveFeedback.light()
        }
        request.onConfirm()
        onDismiss()
    }
}
