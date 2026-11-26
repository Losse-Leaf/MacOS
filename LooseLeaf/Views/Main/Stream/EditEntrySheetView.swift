import SwiftUI
import UniformTypeIdentifiers

/// 修改散页手稿弹窗表单 (EditEntrySheetView)
/// 统一复用 `EntryMediaState` + `EntryMediaAttachmentsSection` 相纸装裱管线：
/// 1. 保留独立 `editLocation` 与散页原生 `editCategory` 选择（日常 / 摄影 / 旅途 / 静物 / 影像）
/// 2. 类型选择收敛至 `EntryType.editableCases`，屏蔽仅系统合成的 `.transaction`（防 HTTP 400）
/// 3. 删空全部附件时显式发送 `clearAttachments: true`（P0 三态解绑契约）
/// 4. 支持整窗拖放照片、聚焦输入框内 `⌘V` 粘贴截图、逐张进度与单张重试
@MainActor
public struct EditEntrySheetView: View {
    public let entry: LifeEntry
    public var onSave: @MainActor (UpdateEntryRequest) async throws -> Void
    public var onCancel: () -> Void

    @State private var editType: EntryType
    @State private var editCategory: EntryCategory
    @State private var editOccurredAt: Date
    @State private var editTitle: String
    @State private var editContent: String
    @State private var editLocation: String
    @State private var editIsPrivate: Bool
    @State private var userEditedTime: Bool = false
    @State private var userEditedLocation: Bool
    @State private var hadPhotosOnStart: Bool
    @State private var media: EntryMediaState
    @State private var isDropTargeted: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?

    @FocusState private var isContentFocused: Bool

    public init(
        entry: LifeEntry,
        onSave: @escaping @MainActor (UpdateEntryRequest) async throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onCancel = onCancel
        let rawType = EntryType(rawValue: entry.type) ?? .life
        let safeType = EntryType.editableCases.contains(rawType) ? rawType : .life
        _editType = State(initialValue: safeType)
        _editCategory = State(initialValue: EntryCategory(normalized: entry.category))
        _editOccurredAt = State(initialValue: FormatUtils.parseFlexDate(entry.occurredAt) ?? Date())
        _editTitle = State(initialValue: entry.title)
        _editContent = State(initialValue: entry.content)
        _editLocation = State(initialValue: entry.location ?? "")
        _editIsPrivate = State(initialValue: entry.isPrivate)
        _userEditedLocation = State(initialValue: !(entry.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        _hadPhotosOnStart = State(initialValue: !entry.attachments.isEmpty)
        _media = State(initialValue: EntryMediaState(initialAttachments: entry.attachments))
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "编辑生活手稿",
            width: ArchiveSheetWidth.standard,
            isSubmitting: isSaving,
            isSubmitDisabled: media.isUploading,
            submitTitle: "保存修改",
            onCancel: onCancel,
            onSubmit: { Task { await save() } }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // 1. 手稿类型切换（日常散页 / 心愿印记）
                HStack(spacing: 6) {
                    Text("类型：")
                        .font(ArchiveTypography.monoScale(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    ForEach(EntryType.editableCases) { t in
                        PaperPillButton(
                            title: t.label,
                            icon: t.symbolName,
                            isSelected: editType == t
                        ) {
                            editType = t
                        }
                    }
                }

                // 1b. 散页原生分类（仅日常散页可选，1:1 映射 Vesper Space 四大展区）
                if editType == .life {
                    EntryCategoryPickerRow(selection: $editCategory, label: "分类：", isCompact: true)
                }

                // 2. 发生时刻
                PaperDatePicker(
                    selection: Binding(
                        get: { editOccurredAt },
                        set: { editOccurredAt = $0; userEditedTime = true }
                    ),
                    enableTime: true,
                    label: "发生时刻："
                )

                // 3. 标题与自适应多行正文
                TextField("标题（可留空由正文第一行派生）", text: $editTitle)
                    .accessibilityLabel("手稿标题")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                    )

                TextField("手稿正文…", text: $editContent, axis: .vertical)
                    .accessibilityLabel("手稿正文")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 13))
                    .lineLimit(6...16)
                    .frame(minHeight: 116, alignment: .topLeading)
                    .focused($isContentFocused)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                    )

                // 4. 具体地点（可选）
                TextField("具体地点（可选，如：街角书店）", text: Binding(
                    get: { editLocation },
                    set: {
                        editLocation = $0
                        userEditedLocation = !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                ))
                    .accessibilityLabel("具体地点")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                    )

                // 5. 照片相纸附件装裱区（共享 EntryMediaAttachmentsSection）
                EntryMediaAttachmentsSection(media: media)

                // 6. 私密开关（统一使用纸本滑动开关 PaperSwitchToggleStyle）
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("仅自己可见（私密）")
                            .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("开启后仅自己可见，不对外公开或同步至 Vesper Space，亦不写入系统 Spotlight")
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $editIsPrivate)
                        .labelsHidden()
                        .toggleStyle(.paperSwitch)
                        .accessibilityLabel("仅自己可见（私密）")
                }
                .padding(.vertical, 4)

                if let activeError = saveError ?? media.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(activeError)
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .lineLimit(3)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .padding(8)
                    .background(ArchivePalette.accentWarm.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("保存失败：\(activeError)")
                }
            }
        }
        .onAppear {
            isContentFocused = true
            media.onPhotoMetadataExtracted = { capturedAt, lat, lon in
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
        }
        .onDrop(of: [.image, .fileURL, .rawImage], isTargeted: $isDropTargeted) { providers in
            media.handleDrop(providers: providers)
        }
        .onPasteImageShortcut {
            media.paste(providers: [])
        }
    }

    private func save() async {
        guard !isSaving, !media.isUploading else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let currentAttachments = media.uploadedAttachments
        let cleanTitle = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = editContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(cleanTitle.isEmpty && cleanContent.isEmpty && currentAttachments.isEmpty) else {
            saveError = "标题、正文与相纸不能同时为空"
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
            try await onSave(req)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
