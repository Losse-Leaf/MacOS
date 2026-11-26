import SwiftUI

/// 三栏工作台 · 中栏按月分组的紧凑散页目录 (Bear / Day One 风格)
/// 采用原生 `List(selection:)` + 可选 `.tag(entry.id as Int?)`，支持键盘 ↑↓ 秒切、远端历史命中、右键菜单与双击开独立窗口。
@MainActor
struct StreamEntryListView: View {
    @Bindable var appState: AppState
    @State private var visibleEntryLimit: Int = 150

    private var displayedEntries: [LifeEntry] {
        appState.displayedStreamEntries
    }

    private var remoteOnlyEntries: [LifeEntry] {
        let q = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let remote = appState.globalSearchResult?.entries else { return [] }
        let localIds = Set(displayedEntries.map(\.id))
        return remote.filter { !localIds.contains($0.id) }
    }

    private var selectedEntryIdBinding: Binding<Int?> {
        Binding(
            get: { appState.highlightedEntry?.id },
            set: { newId in
                guard let newId else {
                    appState.highlightedEntry = nil
                    return
                }
                if let match = displayedEntries.first(where: { $0.id == newId })
                    ?? remoteOnlyEntries.first(where: { $0.id == newId })
                    ?? appState.entries.first(where: { $0.id == newId }) {
                    appState.keyboardFocusedEntryId = match.id
                    appState.highlightedEntry = match
                }
            }
        )
    }

    var body: some View {
        let localEntries = displayedEntries
        let limitedEntries = Array(localEntries.prefix(visibleEntryLimit))
        let monthGroups = AppState.groupEntriesByMonth(limitedEntries)
        let remoteHits = remoteOnlyEntries

        Group {
            if localEntries.isEmpty && remoteHits.isEmpty {
                if appState.isLoading {
                    ArchiveSkeletonView(rowCount: 6, showsHeader: false)
                        .padding(ArchiveSpacing.l)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    emptyListView
                }
            } else {
                List(selection: selectedEntryIdBinding) {
                    let selectedId = appState.highlightedEntry?.id
                    ForEach(monthGroups) { group in
                        Section(group.title) {
                            ForEach(group.entries) { entry in
                                entryRow(for: entry, isSelected: selectedId == entry.id)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                                    .tag(entry.id)
                            }
                        }
                    }

                    if localEntries.count > limitedEntries.count {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("展开更多历史（\(limitedEntries.count) / \(localEntries.count)）")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .onAppear {
                            visibleEntryLimit = min(localEntries.count, visibleEntryLimit + 150)
                        }
                    }

                    if !remoteHits.isEmpty {
                        Section("远端历史归档") {
                            ForEach(remoteHits) { entry in
                                entryRow(for: entry, isSelected: selectedId == entry.id)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                                    .tag(entry.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .tint(ArchivePalette.accentWarm)
            }
        }
        .background(ArchivePalette.archiveSubtle.opacity(0.45))
        .onChange(of: appState.navigation.sidebarDestination) { _, _ in
            visibleEntryLimit = 150
        }
        .onChange(of: appState.searchQuery) { _, _ in
            visibleEntryLimit = 150
        }
    }

    private func entryRow(for entry: LifeEntry, isSelected: Bool) -> some View {
        EntryListRowView(
            entry: entry,
            isSelected: isSelected,
            onOpenWindow: { appState.detailWindowEntry = entry },
            onEdit: {
                appState.highlightedEntry = entry
                appState.navigation.editCurrentEntryRequestToken &+= 1
            },
            onTogglePrivacy: { appState.toggleEntryPrivacy(entry) },
            onReupload: { appState.reuploadEntry(id: entry.id) },
            onDelete: {
                appState.askConfirm(
                    title: ArchiveSharedCopy.entryDeleteTitle,
                    message: ArchiveSharedCopy.entryDeleteMessage,
                    confirmText: ArchiveSharedCopy.entryDeleteConfirmText,
                    danger: true
                ) {
                    appState.deleteEntryAction(entry)
                }
            },
            onCopyNotice: { msg in appState.showTemporaryBanner(msg) }
        )
    }

    private var emptyListView: some View {
        let isSearching = !appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 10) {
            Image(systemName: isSearching ? "magnifyingglass" : "book.pages")
                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.emptyIcon, weight: .light))
                .foregroundStyle(ArchivePalette.inkMuted)
                .accessibilityHidden(true)

            Text(isSearching ? "没有匹配的散页" : "这里尚无散页记录")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .medium))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text(isSearching ? "试试更换关键词，或按 ⌘K 进行跨库搜索" : "写下日常想法、定格照片，或按 ⌘N 记一笔")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkMuted)
                .multilineTextAlignment(.center)

            if !isSearching && appState.isPaired {
                Button("写一篇新散页") {
                    appState.showNewEntrySheet = true
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EntryListRowView: View {
    let entry: LifeEntry
    let isSelected: Bool
    let onOpenWindow: () -> Void
    let onEdit: () -> Void
    let onTogglePrivacy: () -> Void
    let onReupload: () -> Void
    let onDelete: () -> Void
    let onCopyNotice: (String) -> Void

    private var displayTitle: String {
        let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        let firstLine = entry.content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstLine.isEmpty ? (entry.attachments.isEmpty ? "无题散页" : "相纸留影") : firstLine
    }

    private var excerptText: String {
        let trimmedContent = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return "" }
        if entry.hasDistinctTitle {
            return trimmedContent
        }
        let lines = trimmedContent.split(whereSeparator: \.isNewline).dropFirst()
        return lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var compactDateText: String {
        let parsed = entry.parsedDate
        guard parsed.isValid else { return "" }
        let currentYear = String(FormatUtils.beijingCurrentYearMonth().year)
        if let m = Int(parsed.month), let d = Int(parsed.day) {
            if parsed.year == currentYear {
                return "\(m)月\(d)日"
            }
            return "\(parsed.year)/\(m)/\(d)"
        }
        return parsed.dotDate
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.prose, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !excerptText.isEmpty {
                    Text(excerptText)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(2)
                }

                HStack(spacing: 6) {
                    if !compactDateText.isEmpty {
                        Text(compactDateText)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.label))
                            .foregroundStyle(.secondary)
                    }

                    if let loc = entry.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                        Text("· \(loc)")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.label))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if entry.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.tinyIcon))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(ArchivePalette.accentWarm))
                            .accessibilityLabel("仅自己可见")
                    }

                    let syncState = entry.syncStatus ?? "synced"
                    if syncState == "failed" {
                        Text("同步失败")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.miniBadge, weight: .medium))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(ArchivePalette.accentWarm))
                    } else if syncState != "synced" {
                        Text("待同步")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.miniBadge, weight: .medium))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(ArchivePalette.accentWarm))
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if !entry.attachments.isEmpty {
                EntryListThumbnailView(attachments: entry.attachments)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onOpenWindow()
            } label: {
                Label("在新窗口打开", systemImage: "macwindow.badge.plus")
            }

            if entry.id > 0 {
                Button {
                    onEdit()
                } label: {
                    Label("编辑手稿", systemImage: ArchiveIcon.edit.systemName)
                }

                Button {
                    onTogglePrivacy()
                } label: {
                    Label(
                        entry.isPrivate ? "设为公开可见" : "设为仅自己可见（私密）",
                        systemImage: entry.isPrivate ? "lock.open" : "lock.fill"
                    )
                }
            }

            if (entry.syncStatus ?? "synced") != "synced" {
                Button {
                    onReupload()
                } label: {
                    Label("重新上传到中枢", systemImage: ArchiveIcon.sync.systemName)
                }
            }

            Divider()

            Button {
                SecureClipboard.copy(entry.content)
                onCopyNotice("已拷贝手稿正文至剪贴板")
            } label: {
                Label("拷贝正文", systemImage: "doc.on.doc")
            }

            Button {
                SecureClipboard.copy(ArchiveExporter.makeMarkdown(entries: [entry]))
                onCopyNotice("已拷贝 Markdown 格式至剪贴板")
            } label: {
                Label("拷贝 Markdown", systemImage: "text.alignleft")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除手稿", systemImage: ArchiveIcon.delete.systemName)
            }
        }
    }
}
