import SwiftUI
import AppKit

/// 相纸灯箱 (Editorial Lightbox)
/// 从 StreamView 拆出：原文件同时承载主工作台、灯箱、编辑弹窗与详情弹窗四类职责，
/// 单文件过长会拖慢 Swift 增量编译，也让 diff 难以审阅。

/// 暗房全屏沉浸式看图灯箱：支持触控板双指缩放、拖拽平移、双击 2x 放大、键盘左右键切图与原片系统预览
public struct EditorialLightboxView: View {
    @State private var currentAttachment: Attachment
    let allAttachments: [Attachment]
    var onClose: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var noticeText: String?

    public init(attachment: Attachment, allAttachments: [Attachment], onClose: @escaping () -> Void) {
        _currentAttachment = State(initialValue: attachment)
        self.allAttachments = allAttachments
        self.onClose = onClose
    }

    private var currentIndex: Int {
        allAttachments.firstIndex(where: { $0.id == currentAttachment.id }) ?? 0
    }

    public var body: some View {
        ZStack {
            ArchivePalette.inkPrimary.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture {
                    if scale <= 1.0 {
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.25)) {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                }

            VStack(spacing: 16) {
                if let url = APIClient.shared.resolveMediaURL(currentAttachment.url) {
                    ZStack {
                        FilmFrameView(
                            imageURL: url,
                            caption: currentAttachment.originalFilename,
                            metaText: (currentAttachment.width != nil && currentAttachment.height != nil)
                                ? "\(currentAttachment.width!) × \(currentAttachment.height!) px"
                                : nil,
                            maxHeight: 520
                        )
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(max(value, 0.8), 3.5)
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.25)) {
                                        if scale < 1.0 {
                                            scale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            scale > 1.0 ? DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                } : nil
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.25)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 780)

                    // 左右翻页控制器与相册计数指示
                    if allAttachments.count > 1 {
                        HStack(spacing: 20) {
                            Button {
                                changePhoto(by: -1)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("上一张")
                                }
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .disabled(currentIndex == 0)

                            Text("\(currentIndex + 1) / \(allAttachments.count)")
                                .font(ArchiveTypography.monoScale(size: 12, weight: .semibold))
                                .foregroundStyle(ArchivePalette.archivePaper)

                            Button {
                                changePhoto(by: 1)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("下一张")
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .disabled(currentIndex == allAttachments.count - 1)
                        }
                    }

                    // 动作栏
                    HStack(spacing: 10) {
                        Button {
                            openInSystemPreview(url: url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow.on.rectangle")
                                Text("「预览」查看")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .help("使用 macOS 系统原生 Preview 打开原片")

                        Button {
                            copyImageToClipboard(url: url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("拷贝相纸")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                        Button {
                            saveImageToDisk(url: url, filename: currentAttachment.originalFilename)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                Text("导出存储…")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                        Button("关闭 ESC") {
                            onClose()
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                        .keyboardShortcut(.cancelAction)
                    }

                    if let noticeText {
                        Text(noticeText)
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }
            }
            .padding(24)
        }
    }

    private func changePhoto(by delta: Int) {
        let newIdx = currentIndex + delta
        guard allAttachments.indices.contains(newIdx) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
            currentAttachment = allAttachments[newIdx]
        }
    }

    // 关键：三件事统一走 `PaperImageExport`（原先在这里与相纸框里各写了一遍），
    // 而且失败**必须给提示** —— 原先是 `try?` 一把梭，按钮点了毫无反应。
    private func openInSystemPreview(url: URL) {
        Task { @MainActor in
            noticeText = nil
            switch await PaperImageExport.openInSystemPreview(url: url) {
            case .success(let message): noticeText = message
            case .failure(let message): noticeText = "⚠️ \(message)"
            }
        }
    }

    private func copyImageToClipboard(url: URL) {
        Task { @MainActor in
            noticeText = nil
            switch await PaperImageExport.copyToClipboard(url: url) {
            case .success(let message): noticeText = message
            case .failure(let message): noticeText = "⚠️ \(message)"
            }
        }
    }

    private func saveImageToDisk(url: URL, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename.isEmpty ? "looseleaf-photo.jpg" : filename
        if panel.runModal() == .OK, let targetURL = panel.url {
            Task { @MainActor in
                noticeText = nil
                switch await PaperImageExport.exportToDisk(url: url, to: targetURL) {
                case .success(let message): noticeText = message
                case .failure(let message): noticeText = "⚠️ \(message)"
                }
            }
        }
    }
}
