import SwiftUI
import AppKit

/// 暗房全屏沉浸式看图灯箱 (Editorial Lightbox)
public struct EditorialLightboxView: View {
    @State private var currentAttachment: Attachment
    let allAttachments: [Attachment]
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
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

    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    public var body: some View {
        ZStack {
            // 恒定胶片暗房黑底（不随系统深浅色反相为米白）
            Color(red: 0.06, green: 0.06, blue: 0.055)
                .opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture {
                    if scale <= 1.0 {
                        onClose()
                    } else {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.25)) {
                            resetZoom()
                        }
                    }
                }

            VStack(spacing: 16) {
                if let url = currentAttachment.resolvedDisplayURL(preferThumbnail: false) {
                    ZStack {
                        FilmFrameView(
                            imageURL: url,
                            originalURL: url,
                            preferredFilename: currentAttachment.originalFilename,
                            intrinsicSize: currentAttachment.intrinsicSize,
                            caption: currentAttachment.originalFilename,
                            metaText: (currentAttachment.width != nil && currentAttachment.height != nil)
                                ? "\(currentAttachment.width!) × \(currentAttachment.height!) px"
                                : nil,
                            maxHeight: 520,
                            thumbnailMaxPixel: 1_560,
                            onExportNotice: { message in
                                noticeText = message
                            }
                        )
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(max(lastScale * value, 0.8), 4.0)
                                }
                                .onEnded { _ in
                                    withAnimation(reduceMotion ? nil : .spring(response: 0.25)) {
                                        if scale < 1.0 {
                                            resetZoom()
                                        } else {
                                            lastScale = scale
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
                            withAnimation(reduceMotion ? nil : .spring(response: 0.25)) {
                                if scale > 1.0 {
                                    resetZoom()
                                } else {
                                    scale = 2.0
                                    lastScale = 2.0
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 780)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.emptyIcon, weight: .light))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        Text("无法解析该张相纸地址")
                            .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.lead, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                    }
                    .padding(36)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
                }

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
                        .paperButtonFocusRing()
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .disabled(currentIndex == 0)

                        Text("\(currentIndex + 1) / \(allAttachments.count)")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)

                        Button {
                            changePhoto(by: 1)
                        } label: {
                            HStack(spacing: 4) {
                                Text("下一张")
                                Image(systemName: "chevron.right")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .paperButtonFocusRing()
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .disabled(currentIndex == allAttachments.count - 1)
                    }
                }

                HStack(spacing: 10) {
                    if let url = currentAttachment.resolvedDisplayURL(preferThumbnail: false) {
                        Button {
                            openInSystemPreview(url: url, filename: currentAttachment.originalFilename)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow.on.rectangle")
                                Text("「预览」查看")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .paperButtonFocusRing()
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
                        .paperButtonFocusRing()

                        Button {
                            saveImageToDisk(url: url, filename: currentAttachment.originalFilename)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                Text("导出存储…")
                            }
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .paperButtonFocusRing()
                    }

                    Button("关闭 ESC") {
                        onClose()
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    .paperButtonFocusRing()
                    .keyboardShortcut(.cancelAction)
                }

                if let noticeText {
                    Text(noticeText)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.footnote))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
            }
            .padding(24)
        }
        .environment(\.colorScheme, .dark)
    }

    private func changePhoto(by delta: Int) {
        let newIdx = currentIndex + delta
        guard allAttachments.indices.contains(newIdx) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            resetZoom()
            noticeText = nil
            currentAttachment = allAttachments[newIdx]
        }
    }

    private func openInSystemPreview(url: URL, filename: String) {
        Task { @MainActor in
            noticeText = nil
            switch await PaperImageExport.openInSystemPreview(url: url, preferredFilename: filename) {
            case .success(let message), .failure(let message):
                noticeText = message
            }
        }
    }

    private func copyImageToClipboard(url: URL) {
        Task { @MainActor in
            noticeText = nil
            switch await PaperImageExport.copyToClipboard(url: url) {
            case .success(let message), .failure(let message):
                noticeText = message
            }
        }
    }

    private func saveImageToDisk(url: URL, filename: String) {
        Task { @MainActor in
            guard let result = await PaperImageExport.presentSavePanel(url: url, preferredFilename: filename) else {
                return
            }
            switch result {
            case .success(let message), .failure(let message):
                noticeText = message
            }
        }
    }
}
