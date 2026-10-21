// EntryMediaAttachmentsSection.swift
// 创作模态相纸附件区
// 职责：选图 / 拖拽 / 粘贴入口，逐张缩略图 + 进度条 + 状态，以及失败重试与移除。

import SwiftUI

/// 相纸附件区（多选 / 拖拽 / 粘贴 + 逐张进度 + 失败重试 + 移除）
///
/// **性能要点**：本 View 是独立子 View，只订阅 `EntryMediaState` 里的附件与进度字段，
/// 上传进度刷新时重绘的只有这里，不会牵连整个模态窗口。
struct EntryMediaAttachmentsSection: View {
    @Bindable var media: EntryMediaState
    /// 拖拽悬停高亮
    @State private var isMediaDropTargeted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            // 上传总进度（原先 uploadProgress 是死状态，从不展示）
            if media.isUploading {
                HStack(spacing: 8) {
                    ProgressView(value: media.overallProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 180)
                    Text("正在装裱 \(Int(media.overallProgress * 100))%")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .accessibilityLabel("正在装裱相片")
            }

            // 相机底款信息（原先只写不读，用户看不到 EXIF 相机信息）
            if !media.extractedCameraLine.isEmpty {
                Text(media.extractedCameraLine)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .accessibilityLabel("相机信息：\(media.extractedCameraLine)")
            }

            if !media.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(media.items) { item in
                            uploadCard(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - 头部：标题 + 选图按钮 + 拖拽落点

    private var headerRow: some View {
        HStack {
            Text("胶片与图档装裱 (\(media.items.count))")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)

            Spacer()

            Button {
                media.paste(providers: [])
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10.5))
                    Text("粘贴相纸")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            .disabled(media.isUploading)
            .help("从剪贴板粘贴截图或图片文件 (⌘V)")

            Button {
                media.pickAndUploadFromPanel()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 10.5))
                    Text(media.isUploading ? "正在装裱…" : "添加相纸照片")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            .disabled(media.isUploading)
            .help("从「照片」App 或访达拖拽照片到此处亦可装裱")
        }

        // 拖拽装裱：与暗房保持一致的拖入体验
        .onDrop(of: [.image, .fileURL, .rawImage], isTargeted: $isMediaDropTargeted) { providers in
            media.handleDrop(providers: providers)
        }
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(isMediaDropTargeted ? ArchivePalette.accentWarm : .clear, lineWidth: 1.5)
                .padding(.vertical, 4)
                .allowsHitTesting(false)
        )
    }

    // MARK: - 单张相纸卡片

    /// 单张相纸卡片：缩略图 + 状态 + 进度条 + 重试 / 移除
    private func uploadCard(_ item: EntryUploadItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                thumbnail(for: item)

                Button {
                    media.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .help("移除这张相纸")
            }
            .frame(width: 72, height: 72)

            // 状态行
            HStack(spacing: 3) {
                Image(systemName: item.status.icon)
                    .font(.system(size: 8))
                Text(item.status.label)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
            }
            .foregroundStyle(statusColor(for: item.status))
            .accessibilityLabel("相纸状态：\(item.status.label)")

            // 逐张进度条
            if item.status == .pending || item.status == .uploading {
                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 72)
                    .accessibilityLabel("正在装裱 \(Int(item.progress * 100))%")
            }

            // 失败重试
            if item.status == .failed {
                Button {
                    media.retry(item)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                        Text("重试")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .help(item.errorMessage ?? "重新装裱这张相纸")
            }
        }
        .frame(width: 72, alignment: .leading)
    }

    /// 相纸缩略图：优先本地预览，上传成功后改用服务端图档
    private func thumbnail(for item: EntryUploadItem) -> some View {
        Group {
            if let local = item.localThumbnail {
                Image(nsImage: local)
                    .interpolation(.high)
                    .antialiased(true)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                    )
            } else if let attachment = item.attachment,
                      let url = APIClient.shared.resolveMediaURL(attachment.url) {
                CachedFilmImageView(url: url, maxHeight: 72)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ArchivePalette.archiveSubtle)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                    )
            }
        }
    }

    /// 状态配色
    private func statusColor(for status: EntryUploadStatus) -> Color {
        switch status {
        case .pending: return ArchivePalette.inkMuted
        case .uploading: return ArchivePalette.accentWarm
        case .succeeded: return ArchivePalette.accentMoss
        case .failed: return ArchivePalette.accentWarm
        }
    }
}
