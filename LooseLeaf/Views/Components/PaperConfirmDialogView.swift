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

    public init(request: ConfirmDialogRequest, onDismiss: @escaping () -> Void) {
        self.request = request
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.42)
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
                    }

                    Text(request.title)
                        .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Spacer()

                    Button {
                        cancelAction()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("取消关闭 (Esc)")
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                Divider()
                    .overlay(ArchivePalette.borderSubtle.opacity(0.8))

                // 2. 正文提示词
                Text(request.message)
                    .font(ArchiveTypography.editorialSerif(size: 13.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
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
                            .font(ArchiveTypography.monoScale(size: 12))
                            .foregroundStyle(isHoveringCancel ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringCancel = $0 }

                    // 确认按钮 (主操作)
                    Button {
                        confirmAction()
                    } label: {
                        Text(request.confirmText)
                            .font(ArchiveTypography.monoScale(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.archivePaper)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(request.danger ? ArchivePalette.accentWarm : ArchivePalette.inkPrimary)
                            )
                            .opacity(isHoveringConfirm ? 0.9 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringConfirm = $0 }
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
            confirmAction()
            return .handled
        }
    }

    private func cancelAction() {
        AudioFeedback.shared.playTink()
        request.onCancel?()
        onDismiss()
    }

    private func confirmAction() {
        if request.danger {
            AudioFeedback.shared.playShutter()
        } else {
            AudioFeedback.shared.playTink()
        }
        request.onConfirm()
        onDismiss()
    }
}
