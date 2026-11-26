import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 散页中栏列表右侧 54×54 圆角缩略图（多图时右下角展示 +N 计数徽标）
public struct EntryListThumbnailView: View {
    public let attachments: [Attachment]

    public init(attachments: [Attachment]) {
        self.attachments = attachments
    }

    public var body: some View {
        if let first = attachments.first,
           let url = first.resolvedDisplayURL(preferThumbnail: true) {
            ZStack(alignment: .bottomTrailing) {
                CachedFilmImageView(
                    url: url,
                    maxHeight: 54,
                    maxPixelOverride: 160,
                    intrinsicSize: first.intrinsicSize,
                    contentMode: .fill,
                    fillsFrame: true
                )
                .frame(width: 54, height: 54)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(ArchivePalette.borderSubtle.opacity(0.6), lineWidth: 0.5)
                )

                if attachments.count > 1 {
                    Text("+\(attachments.count - 1)")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.miniBadge, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.black.opacity(0.62))
                        .clipShape(Capsule())
                        .padding(3)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// 现代无边框自适应图片网格（替代厚重相纸白框，1/2/3/4+ 张自适应排版，点击进暗房大图）
public struct EntryMediaGridView: View {
    public let attachments: [Attachment]
    public var titleHint: String? = nil
    public var onOpenAttachment: (Attachment) -> Void
    public var onNotice: ((String) -> Void)? = nil

    public init(
        attachments: [Attachment],
        titleHint: String? = nil,
        onOpenAttachment: @escaping (Attachment) -> Void,
        onNotice: ((String) -> Void)? = nil
    ) {
        self.attachments = attachments
        self.titleHint = titleHint
        self.onOpenAttachment = onOpenAttachment
        self.onNotice = onNotice
    }

    public var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else if attachments.count == 1, let single = attachments.first {
            EntryMediaTile(
                attachment: single,
                titleHint: titleHint,
                maxHeight: 460,
                fillsFrame: false,
                onTap: { onOpenAttachment(single) },
                onNotice: onNotice
            )
        } else if attachments.count == 2 {
            HStack(spacing: 8) {
                ForEach(attachments) { att in
                    EntryMediaTile(
                        attachment: att,
                        titleHint: titleHint,
                        maxHeight: 280,
                        fillsFrame: true,
                        onTap: { onOpenAttachment(att) },
                        onNotice: onNotice
                    )
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                }
            }
        } else if attachments.count == 3 {
            VStack(spacing: 8) {
                EntryMediaTile(
                    attachment: attachments[0],
                    titleHint: titleHint,
                    maxHeight: 340,
                    fillsFrame: true,
                    onTap: { onOpenAttachment(attachments[0]) },
                    onNotice: onNotice
                )
                .aspectRatio(16.0 / 10.0, contentMode: .fit)

                HStack(spacing: 8) {
                    ForEach(attachments.dropFirst()) { att in
                        EntryMediaTile(
                            attachment: att,
                            titleHint: titleHint,
                            maxHeight: 240,
                            fillsFrame: true,
                            onTap: { onOpenAttachment(att) },
                            onNotice: onNotice
                        )
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    }
                }
            }
        } else {
            let columnCount = attachments.count == 4 ? 2 : 3
            let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(attachments) { att in
                    EntryMediaTile(
                        attachment: att,
                        titleHint: titleHint,
                        maxHeight: 240,
                        fillsFrame: true,
                        onTap: { onOpenAttachment(att) },
                        onNotice: onNotice
                    )
                    .aspectRatio(attachments.count == 4 ? (4.0 / 3.0) : 1.0, contentMode: .fit)
                }
            }
        }
    }
}

/// 单张无边框圆角图片切片（支持点击看大图、拖拽导出原图与右键菜单）
private struct EntryMediaTile: View {
    let attachment: Attachment
    var titleHint: String?
    var maxHeight: CGFloat
    var fillsFrame: Bool
    var onTap: () -> Void
    var onNotice: ((String) -> Void)?

    @State private var isHovering: Bool = false

    private var displayURL: URL? {
        attachment.resolvedDisplayURL(preferThumbnail: true)
    }

    private var originalURL: URL? {
        attachment.resolvedDisplayURL(preferThumbnail: false) ?? displayURL
    }

    var body: some View {
        if let url = displayURL {
            Group {
                if fillsFrame {
                    CachedFilmImageView(
                        url: url,
                        maxHeight: maxHeight,
                        maxPixelOverride: Int(maxHeight * 2),
                        intrinsicSize: attachment.intrinsicSize,
                        contentMode: .fill,
                        fillsFrame: true
                    )
                } else {
                    CachedFilmImageView(
                        url: url,
                        maxHeight: maxHeight,
                        maxPixelOverride: Int(maxHeight * 2),
                        intrinsicSize: attachment.intrinsicSize,
                        contentMode: .fit,
                        fillsFrame: false
                    )
                }
            }
            .background(ArchivePalette.archiveSubtle.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isHovering ? ArchivePalette.accentWarm.opacity(0.45) : ArchivePalette.borderSubtle.opacity(0.55),
                        lineWidth: isHovering ? 1.0 : 0.5
                    )
            )
            .opacity(isHovering ? 0.96 : 1.0)
            .onHover { isHovering = $0 }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(attachment.originalFilename.isEmpty ? (titleHint ?? "散页配图") : attachment.originalFilename)
            .onDrag { makeDragProvider() }
            .contextMenu {
                if let exportURL = originalURL {
                    Button {
                        Task { @MainActor in
                            switch await PaperImageExport.copyToClipboard(url: exportURL) {
                            case .success(let msg), .failure(let msg): onNotice?(msg)
                            }
                        }
                    } label: {
                        Label("拷贝图片", systemImage: "doc.on.doc")
                    }

                    Button {
                        let hint = attachment.originalFilename.isEmpty ? titleHint : attachment.originalFilename
                        Task { @MainActor in
                            switch await PaperImageExport.openInSystemPreview(url: exportURL, preferredFilename: hint) {
                            case .success(let msg), .failure(let msg): onNotice?(msg)
                            }
                        }
                    } label: {
                        Label("在系统「预览」中查看", systemImage: "macwindow.on.rectangle")
                    }

                    Button {
                        let hint = attachment.originalFilename.isEmpty ? titleHint : attachment.originalFilename
                        Task { @MainActor in
                            guard let res = await PaperImageExport.presentSavePanel(url: exportURL, preferredFilename: hint) else { return }
                            switch res {
                            case .success(let msg), .failure(let msg): onNotice?(msg)
                            }
                        }
                    } label: {
                        Label("导出原图…", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
    }

    private func makeDragProvider() -> NSItemProvider {
        guard let url = originalURL else { return NSItemProvider() }
        let provider = NSItemProvider()
        let hint = attachment.originalFilename.isEmpty ? titleHint : attachment.originalFilename
        provider.suggestedName = (PaperImageExport.normalizedFilename(hint, fallbackURL: url) as NSString).deletingPathExtension
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.image.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            Task { @MainActor in
                do {
                    let data = try await PaperImageExport.data(for: url)
                    let safeName = PaperImageExport.normalizedFilename(hint, fallbackURL: url, data: data)
                        .replacingOccurrences(of: "/", with: "-")
                    let dropDir = SyncManager.sharedStorageDirectory.appendingPathComponent("PreviewStaging", isDirectory: true)
                    try? FileManager.default.createDirectory(at: dropDir, withIntermediateDirectories: true)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dropDir.path)
                    let fileURL = dropDir.appendingPathComponent("drag-\(UUID().uuidString.prefix(8))-\(safeName)")
                    try data.write(to: fileURL, options: .atomic)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
                    completion(fileURL, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }
}
