import SwiftUI
import AppKit

    struct TimelineEntryCardView: View {
        let entry: LifeEntry
        @Bindable var appState: AppState
        var onEditEntry: () -> Void
        var onDeleteEntry: () -> Void
        var onEditTransaction: (Transaction) -> Void
        var onDeleteTransaction: (Transaction) -> Void
        var onToggleFeatured: () -> Void
        var onOpenDetail: () -> Void

        @State private var isHovering: Bool = false

        private var parsed: FormatUtils.ParsedBeijingDate {
            entry.parsedDate
        }

        private var typeAccentColor: Color {
            switch entry.type {
            case "travel": return ArchivePalette.accentWarm
            case "project": return Color("SpectrumStudy", bundle: ArchiveResourceBundle.bundle)
            case "wish": return Color("SpectrumLeisure", bundle: ArchiveResourceBundle.bundle)
            case "transaction": return Color("SpectrumDining", bundle: ArchiveResourceBundle.bundle)
            default: return ArchivePalette.accentMoss
            }
        }

        private var entryTypeBadgeName: String {
            switch entry.type {
            case "travel": return "山川游历"
            case "project": return "造物演进"
            case "wish": return "心愿印记"
            case "transaction": return "柴米油盐"
            default: return "日常随笔"
            }
        }

        var body: some View {
            HStack(alignment: .top, spacing: 0) {
                // 左侧时光彩色印线 (2.5pt 细微边缘色标)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(typeAccentColor.opacity(0.85))
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.trailing, 14)

                VStack(alignment: .leading, spacing: 10) {
                    // 顶栏：形态印章 + 北京时间戳 + 地点 + 悬停优雅动作
                    HStack(spacing: 8) {
                        Text(entryTypeBadgeName)
                            .font(ArchiveTypography.monoScale(size: 10.5, weight: .medium))
                            .foregroundStyle(typeAccentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(typeAccentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                        Text(parsed.dotDateTime)
                            .font(ArchiveTypography.monoScale(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)

                        if let loc = entry.location ?? entry.cityName, !loc.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "location")
                                    .font(.system(size: 9.5))
                                Text(loc)
                                    .font(ArchiveTypography.bodySans(size: 11))
                            }
                            .foregroundStyle(ArchivePalette.inkMuted)
                        }

                        if entry.featured == true {
                            Text("精选")
                                .font(ArchiveTypography.monoScale(size: 10, weight: .medium))
                                .foregroundStyle(ArchivePalette.accentMoss)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                        .stroke(ArchivePalette.accentMoss.opacity(0.4), lineWidth: 0.5)
                                )
                        }

                        if (entry.syncStatus ?? "synced") != "synced" {
                            Text("待同步")
                                .font(ArchiveTypography.monoScale(size: 10))
                                .foregroundStyle(ArchivePalette.accentWarm)
                        }

                        Spacer()

                        // 右侧操作：仅在鼠标悬停时优雅淡现，默认保持日记纯粹无噪点
                        HStack(spacing: 6) {
                            if isHovering {
                                if entry.type == "transaction" {
                                    let txId = entry.associatedTransactionId ?? Int64(entry.id)
                                    if let tx = appState.transactionById[Int(txId)] {
                                        Button {
                                            onEditTransaction(tx)
                                        } label: {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 11))
                                                .foregroundStyle(ArchivePalette.inkSecondary)
                                                .frame(width: 24, height: 24)
                                                .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("编辑账目")
                                        .accessibilityLabel("编辑账目")

                                        Button {
                                            onDeleteTransaction(tx)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundStyle(ArchivePalette.accentWarm)
                                                .frame(width: 24, height: 24)
                                                .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("删除账目")
                                        .accessibilityLabel("删除账目")
                                    }
                                } else {
                                    Button {
                                        onToggleFeatured()
                                    } label: {
                                        Image(systemName: entry.featured == true ? "star.fill" : "star")
                                            .font(.system(size: 11))
                                            .foregroundStyle(entry.featured == true ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                                            .frame(width: 24, height: 24)
                                            .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help(entry.featured == true ? "取消精选" : "设为精选")
                                        .accessibilityLabel(entry.featured == true ? "取消精选" : "设为精选")

                                    Button {
                                        onEditEntry()
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 11))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                            .frame(width: 24, height: 24)
                                            .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("编辑手稿")
                                        .accessibilityLabel("编辑手稿")

                                    Button {
                                        onDeleteEntry()
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundStyle(ArchivePalette.accentWarm)
                                            .frame(width: 24, height: 24)
                                            .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("删除手稿")
                                        .accessibilityLabel("删除手稿")
                                }
                            }

                            Button {
                                onOpenDetail()
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .frame(width: 24, height: 24)
                                    .background(isHovering ? ArchivePalette.archiveSubtle.opacity(0.8) : Color.clear)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("查看手稿完整详情")
                                .accessibilityLabel("查看手稿完整详情")
                        }
                        .animation(.easeInOut(duration: 0.15), value: isHovering)
                    }

                    if !entry.title.isEmpty {
                        Text(entry.title)
                            .font(ArchiveTypography.editorialSerif(size: 17.5, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                    }

                    Text(entry.content)
                        .font(ArchiveTypography.bodySans(size: 13.5))
                        .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.92))
                        .lineSpacing(5)
                        .textSelection(.enabled)

                    // 附件胶片相框画廊 (.film-frame)
                    if !entry.attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(entry.attachments) { att in
                                    if let url = APIClient.shared.resolveMediaURL(att.url) {
                                        FilmFrameView(
                                            imageURL: url,
                                            caption: entry.title.isEmpty ? att.originalFilename : entry.title,
                                            metaText: parsed.dotDate,
                                            maxHeight: 220
                                        ) {
                                            appState.lightboxAttachment = att
                                        }
                                        .frame(width: 260)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(16)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
            .paperElevation(isHovering ? 2 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.md)
                    .stroke(
                        appState.keyboardFocusedEntryId == entry.id ? ArchivePalette.accentWarm : Color.clear,
                        lineWidth: 1.0
                    )
            )
            .onHover { isHovering = $0 }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onOpenDetail()
            }
            .contextMenu {
                if entry.type == "transaction" {
                    let txId = entry.associatedTransactionId ?? Int64(entry.id)
                    if let tx = appState.transactionById[Int(txId)] {
                        Button {
                            onEditTransaction(tx)
                        } label: {
                            Label("编辑账目", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDeleteTransaction(tx)
                        } label: {
                            Label("删除账目", systemImage: "trash")
                        }
                        Divider()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(FormatUtils.formattedYuan(cents: tx.amount), forType: .string)
                            appState.showTemporaryBanner("已拷贝金额至剪贴板")
                        } label: {
                            Label("拷贝金额", systemImage: "doc.on.doc")
                        }
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(tx.title.isEmpty ? tx.category : tx.title, forType: .string)
                            appState.showTemporaryBanner("已拷贝账目摘要至剪贴板")
                        } label: {
                            Label("拷贝账目摘要", systemImage: "text.quote")
                        }
                    }
                } else {
                    Button {
                        onOpenDetail()
                    } label: {
                        Label("查看手稿详情", systemImage: "book.pages")
                    }
                    Button {
                        onToggleFeatured()
                    } label: {
                        Label(entry.featured == true ? "取消精选印记" : "标记为精选印记", systemImage: entry.featured == true ? "star.slash" : "star")
                    }
                    Button {
                        onEditEntry()
                    } label: {
                        Label("编辑手稿", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDeleteEntry()
                    } label: {
                        Label("删除手稿", systemImage: "trash")
                    }
                    Divider()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.content, forType: .string)
                        appState.showTemporaryBanner("已拷贝手稿正文至剪贴板")
                    } label: {
                        Label("拷贝手稿正文", systemImage: "doc.on.doc")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(parsed.dotDateTime, forType: .string)
                        appState.showTemporaryBanner("已拷贝时间戳至剪贴板")
                    } label: {
                        Label("拷贝时间戳", systemImage: "clock")
                    }
                }
            }
            .paperHover()
        }
    }
