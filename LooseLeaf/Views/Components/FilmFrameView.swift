import SwiftUI
import AppKit

/// 胶片暗房装裱边框组件 (.film-frame)
/// 严格遵循 docs/ecosystem.md §4.1.2 规范：
/// 四周预留哑光衬纸留白，底部以等宽字体标注底片元数据与拍摄时间，带有相纸贴在日记本上的物理微隆起阴影
public struct FilmFrameView: View {
    public var imageURL: URL?
    public var localImage: NSImage?
    public var caption: String?
    public var metaText: String?
    public var maxHeight: CGFloat
    public var onTap: (() -> Void)?

    public init(
        imageURL: URL? = nil,
        localImage: NSImage? = nil,
        caption: String? = nil,
        metaText: String? = nil,
        maxHeight: CGFloat = 280,
        onTap: (() -> Void)? = nil
    ) {
        self.imageURL = imageURL
        self.localImage = localImage
        self.caption = caption
        self.metaText = metaText
        self.maxHeight = maxHeight
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                ArchivePalette.archivePaper

                if let localImage {
                    Image(nsImage: localImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: maxHeight)
                        .clipped()
                } else if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            VStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("暗房显影中…")
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: maxHeight)
                                .clipped()
                        case .failure:
                            VStack(spacing: 6) {
                                Image(systemName: "photo.artframe")
                                    .font(.system(size: 22))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text("相纸载入暂缓")
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
            )

            if hasFooter {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(ArchiveTypography.editorialSerif(size: 12))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let metaText, !metaText.isEmpty {
                        Text(metaText)
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
        )
        .shadow(color: ArchivePalette.inkPrimary.opacity(0.08), radius: 10, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    private var hasFooter: Bool {
        !(caption ?? "").isEmpty || !(metaText ?? "").isEmpty
    }
}
