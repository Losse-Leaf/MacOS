import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 三栏工作台 · 右栏沉浸阅读与原地编辑画布
/// 默认纯净阅读（居中舒适行宽 + 无边框自适应圆角图片网格 + 正文自由划词）；
/// 点击编辑或按 `⌘E` 原地切换为编辑态，支持改标题、正文、分类、地点、时间、私密态与增删附件。
@MainActor
struct StreamEntryReaderView: View {
    @Bindable var appState: AppState

    @State private var hydratedEntry: LifeEntry?
    @State private var isEditing: Bool = false

    // 原地编辑态草稿字段
    @State private var editType: EntryType = .life
    @State private var editCategory: EntryCategory = .daily
    @State private var editOccurredAt: Date = Date()
    @State private var editTitle: String = ""
    @State private var editContent: String = ""
    @State private var editLocation: String = ""
    @State private var editIsPrivate: Bool = false
    @State private var userEditedTime: Bool = false
    @State private var userEditedLocation: Bool = false
    @State private var hadPhotosOnStart: Bool = false
    @State private var editMedia = EntryMediaState()
    @State private var isDropTargeted: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @FocusState private var isContentFocused: Bool

    private var activeEntry: LifeEntry? {
        guard let selected = appState.highlightedEntry else { return nil }
        if let hydratedEntry, hydratedEntry.id == selected.id {
            return hydratedEntry
        }
        return appState.entries.first(where: { $0.id == selected.id }) ?? selected
    }

    var body: some View {
        Group {
            if let entry = activeEntry {
                if isEditing {
                    inlineEditorView(for: entry)
                } else {
                    immersiveReaderView(for: entry)
                }
            } else {
                emptySelectionView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchivePalette.archivePaper)
        .task(id: appState.highlightedEntry?.id) {
            hydratedEntry = nil
            guard let target = appState.highlightedEntry,
                  target.id > 0,
                  target.type != "transaction",
                  !appState.entries.contains(where: { $0.id == target.id }) else { return }
            if let remote = try? await APIClient.shared.fetchEntry(id: target.id) {
                hydratedEntry = remote
            }
        }
        .onChange(of: appState.highlightedEntry?.id) { _, _ in
            isEditing = false
            saveError = nil
        }
        .onChange(of: appState.navigation.editCurrentEntryRequestToken) { _, _ in
            guard appState.navigation.sidebarDestination.isStreamDestination,
                  let entry = activeEntry,
                  entry.id > 0,
                  entry.type != "transaction",
                  appState.isPaired else { return }
            if isEditing {
                isEditing = false
            } else {
                beginEditing(entry)
            }
        }
    }

    // MARK: - 1. 纯净阅读态

    private func immersiveReaderView(for entry: LifeEntry) -> some View {
        VStack(spacing: 0) {
            readerTopBar(for: entry)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.45))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        Text(entry.parsedDate.dotDateTime)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(ArchivePalette.inkMuted)

                        if let loc = entry.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                            Text("· \(loc)")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                    }

                    if entry.hasDistinctTitle {
                        Text(entry.title)
                            .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.hero, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                            .textSelection(.enabled)
                    }

                    if !entry.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        EditorialProseTextView(
                            entry.content,
                            font: ArchiveTypography.bodySans(size: ArchiveTypography.Scale.lead),
                            color: ArchivePalette.inkPrimary,
                            lineSpacing: 7
                        )
                        .textSelection(.enabled)
                    }

                    if !entry.attachments.isEmpty {
                        EntryMediaGridView(
                            attachments: entry.attachments,
                            titleHint: entry.title.isEmpty ? nil : entry.title,
                            onOpenAttachment: { att in
                                appState.lightboxAttachment = att
                            },
                            onNotice: { message in
                                appState.showTemporaryBanner(message)
                            }
                        )
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .frame(maxWidth: 740, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func readerTopBar(for entry: LifeEntry) -> some View {
        let syncState = entry.syncStatus ?? "synced"
        return HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(entry.displayAccentColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(entry.displayBadgeLabel)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                    .foregroundStyle(entry.displayAccentColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(entry.displayAccentColor.opacity(0.10))
            .clipShape(Capsule())

            if entry.isPrivate {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill")
                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.badge))
                    Text("私密")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                }
                .foregroundStyle(ArchivePalette.accentWarm)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ArchivePalette.accentWarm.opacity(0.10))
                .clipShape(Capsule())
            }

            if syncState != "synced" {
                Button {
                    appState.reuploadEntry(id: entry.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: ArchiveIcon.sync.systemName)
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.badge))
                        Text(syncState == "failed" ? "同步失败 · 点击重传" : "待同步 · 点击重传")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                    }
                    .foregroundStyle(ArchivePalette.accentWarm)
                }
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
            }

            Spacer()

            if appState.isPaired {
                HStack(spacing: 4) {
                    if entry.id > 0 {
                        PaperIconButton(
                            systemName: ArchiveIcon.edit.systemName,
                            label: "编辑散页",
                            help: "原地编辑散页 (⌘E)",
                            size: ArchiveTypography.Scale.body,
                            tint: ArchivePalette.inkSecondary
                        ) {
                            beginEditing(entry)
                        }

                        PaperIconButton(
                            systemName: entry.isPrivate ? "lock.open" : "lock.fill",
                            label: entry.isPrivate ? "设为公开可见" : "设为仅自己可见",
                            size: ArchiveTypography.Scale.body,
                            tint: entry.isPrivate ? ArchivePalette.accentWarm : ArchivePalette.inkSecondary
                        ) {
                            appState.toggleEntryPrivacy(entry)
                        }
                    }

                    PaperIconButton(
                        systemName: "macwindow.badge.plus",
                        label: "在新窗口打开",
                        help: "在独立窗口打开 (⌘↩)",
                        size: ArchiveTypography.Scale.body,
                        tint: ArchivePalette.inkSecondary
                    ) {
                        appState.detailWindowEntry = entry
                    }

                    PaperIconButton(
                        systemName: ArchiveIcon.delete.systemName,
                        label: "删除散页",
                        size: ArchiveTypography.Scale.body,
                        tint: ArchivePalette.accentWarm
                    ) {
                        appState.askConfirm(
                            title: ArchiveSharedCopy.entryDeleteTitle,
                            message: ArchiveSharedCopy.entryDeleteMessage,
                            confirmText: ArchiveSharedCopy.entryDeleteConfirmText,
                            danger: true
                        ) {
                            appState.deleteEntryAction(entry)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
    }

    // MARK: - 2. 原地编辑态（⌘E 切换，复用三态附件与更新契约）

    private func beginEditing(_ entry: LifeEntry) {
        let rawType = EntryType(rawValue: entry.type) ?? .life
        editType = EntryType.editableCases.contains(rawType) ? rawType : .life
        editCategory = EntryCategory(normalized: entry.category)
        editOccurredAt = FormatUtils.parseFlexDate(entry.occurredAt) ?? Date()
        editTitle = entry.title
        editContent = entry.content
        editLocation = entry.location ?? ""
        editIsPrivate = entry.isPrivate
        userEditedTime = false
        userEditedLocation = !(entry.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        hadPhotosOnStart = !entry.attachments.isEmpty
        editMedia = EntryMediaState(initialAttachments: entry.attachments)
        editMedia.onPhotoMetadataExtracted = { capturedAt, lat, lon in
            if let capturedAt, !hadPhotosOnStart, !userEditedTime, let date = FormatUtils.parseFlexDate(capturedAt) {
                editOccurredAt = date
            }
            if let lat, let lon, editLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !userEditedLocation {
                Task { @MainActor in
                    if let resolved = await ImageProcessor.reverseGeocodeLocation(latitude: lat, longitude: lon),
                       editLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !userEditedLocation {
                        editLocation = resolved
                    }
                }
            }
        }
        saveError = nil
        isEditing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            isContentFocused = true
        }
    }

    private func inlineEditorView(for entry: LifeEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("正在编辑散页")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)

                Spacer()

                Button("取消") {
                    isEditing = false
                    saveError = nil
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await saveInlineEdit(for: entry) }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("保存 (⌘↵)")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
                .disabled(isSaving || editMedia.isUploading)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.45))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 轻量元信息行
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            ForEach(EntryType.editableCases) { t in
                                PaperPillButton(
                                    title: t.label,
                                    icon: t.symbolName,
                                    isSelected: editType == t,
                                    isCompact: true
                                ) {
                                    editType = t
                                }
                            }

                            Spacer()

                            Toggle(isOn: $editIsPrivate) {
                                HStack(spacing: 4) {
                                    Image(systemName: editIsPrivate ? "lock.fill" : "lock.open")
                                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.label))
                                        .foregroundStyle(editIsPrivate ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                                    Text("仅自己可见")
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.footnote))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                }
                            }
                            .toggleStyle(.paperSwitch)
                        }

                        if editType == .life {
                            EntryCategoryPickerRow(selection: $editCategory, label: "分类：", isCompact: true)
                        }

                        HStack(spacing: 12) {
                            PaperDatePicker(
                                selection: Binding(
                                    get: { editOccurredAt },
                                    set: { editOccurredAt = $0; userEditedTime = true }
                                ),
                                enableTime: true,
                                label: "时刻："
                            )

                            TextField("地点（可选）", text: Binding(
                                get: { editLocation },
                                set: {
                                    editLocation = $0
                                    userEditedLocation = !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                }
                            ))
                            .accessibilityLabel("具体地点")
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .frame(maxWidth: 200)
                            .background(ArchivePalette.archiveSubtle.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                        }
                    }

                    Divider().overlay(ArchivePalette.borderSubtle.opacity(0.4))

                    TextField("标题（可留空由正文第一行派生）", text: $editTitle)
                        .accessibilityLabel("手稿标题")
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.hero, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    TextField("写下此刻…", text: $editContent, axis: .vertical)
                        .accessibilityLabel("手稿正文")
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.lead))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineSpacing(6)
                        .lineLimit(8...30)
                        .frame(minHeight: 180, alignment: .topLeading)
                        .focused($isContentFocused)

                    EntryMediaAttachmentsSection(media: editMedia)

                    if let activeError = saveError ?? editMedia.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.caption))
                            Text(activeError)
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.footnote))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(10)
                        .background(ArchivePalette.accentWarm.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 24)
                .frame(maxWidth: 740, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.md)
                .strokeBorder(
                    isDropTargeted ? ArchivePalette.accentWarm : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .padding(8)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.image, .fileURL, .rawImage], isTargeted: $isDropTargeted) { providers in
            editMedia.handleDrop(providers: providers)
        }
        .onPasteImageShortcut {
            editMedia.paste(providers: [])
        }
    }

    private func saveInlineEdit(for entry: LifeEntry) async {
        guard !isSaving, !editMedia.isUploading else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let currentAttachments = editMedia.uploadedAttachments
        let cleanTitle = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = editContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(cleanTitle.isEmpty && cleanContent.isEmpty && currentAttachments.isEmpty) else {
            saveError = "标题、正文与配图不能同时为空"
            return
        }
        let cleanLoc = editLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldClearAttachments = !entry.attachments.isEmpty && currentAttachments.isEmpty
        let req = UpdateEntryRequest(
            type: editType.rawValue,
            category: editType == .life ? editCategory.rawValue : "",
            title: cleanTitle,
            content: cleanContent,
            occurredAt: FormatUtils.beijingISOString(from: editOccurredAt),
            location: cleanLoc,
            isPrivate: editIsPrivate,
            attachmentIds: currentAttachments.map(\.id),
            clearAttachments: shouldClearAttachments ? true : nil
        )
        do {
            let updated = try await APIClient.shared.updateEntry(id: entry.id, req)
            await appState.loadEntries(forceFull: false)
            await appState.loadConfigAndProfile()
            let liveUpdated = appState.entries.first(where: { $0.id == entry.id }) ?? updated
            appState.highlightedEntry = liveUpdated
            hydratedEntry = liveUpdated
            isEditing = false
            appState.showTemporaryBanner("已保存散页修订")
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var emptySelectionView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.emptyIcon, weight: .light))
                .foregroundStyle(ArchivePalette.inkMuted.opacity(0.6))
                .accessibilityHidden(true)
            Text("选择一篇散页开始阅读")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)
            Text("按 ↑ / ↓ 切换散页，或按 ⌘N 写下此刻")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
