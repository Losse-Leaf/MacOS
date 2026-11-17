import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 修改散页手稿弹窗表单 (EditEntrySheetView)
/// 修复：
/// 1. 拆分独立 `editLocation` 与 `editCityCode/editCityName`，根除保存修订时将细粒度地点覆盖为城市名的缺陷
/// 2. 类型选择收敛至 `EntryType.editableCases`，屏蔽仅系统合成的 `.transaction` / `.gear`（防 HTTP 400）
/// 3. 删空全部附件时显式发送 `clearAttachments: true`（P0 三态解绑契约）
/// 4. 补齐整窗拖放照片、聚焦输入框内 `⌘V` 粘贴截图、异步 `NSOpenPanel` 与 `PaperSwitchToggleStyle`
@MainActor
public struct EditEntrySheetView: View {
    public let entry: LifeEntry
    public var onSave: @MainActor (UpdateEntryRequest) async throws -> Void
    public var onCancel: () -> Void

    @State private var editType: EntryType
    @State private var editOccurredAt: Date
    @State private var editTitle: String
    @State private var editContent: String
    @State private var editLocation: String
    @State private var editCityCode: String
    @State private var editCityName: String
    @State private var editAttachments: [Attachment]
    @State private var editIsPrivate: Bool
    @State private var isUploading: Bool = false
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
        _editOccurredAt = State(initialValue: FormatUtils.parseFlexDate(entry.occurredAt) ?? Date())
        _editTitle = State(initialValue: entry.title)
        _editContent = State(initialValue: entry.content)
        _editLocation = State(initialValue: entry.location ?? "")
        _editCityCode = State(initialValue: entry.cityCode ?? "")
        _editCityName = State(initialValue: entry.cityName ?? "")
        _editAttachments = State(initialValue: entry.attachments)
        _editIsPrivate = State(initialValue: entry.isPrivate)
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "编辑生活手稿",
            width: ArchiveSheetWidth.standard,
            isSubmitting: isSaving,
            isSubmitDisabled: isUploading,
            submitTitle: "保存修改",
            onCancel: onCancel,
            onSubmit: { Task { await save() } }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // 1. 手稿类型切换（仅暴露合法四维类型）
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

                // 2. 发生时刻
                PaperDatePicker(selection: $editOccurredAt, enableTime: true, label: "发生时刻：")

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

                // 4. 行政省市与细粒度具体地点独立并列（互不覆盖）
                HStack(spacing: 10) {
                    PaperCityPicker(
                        selectedCode: $editCityCode,
                        selectedName: $editCityName,
                        placeholder: "选择城市…"
                    )

                    TextField("具体地点（可选，如：街角书店）", text: $editLocation)
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
                }

                // 5. 照片相纸附件管理与拖拽/粘贴增补
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("手账影像相纸 (\(editAttachments.count))")
                            .font(ArchiveTypography.editorialSerif(size: 13, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)

                        Spacer()

                        if isUploading {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("相纸上传中…")
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                            }
                        } else {
                            Button("粘贴图片") {
                                pasteFromClipboard()
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .paperButtonFocusRing()

                            Button("+ 补选相纸照片") {
                                selectPhotosForEdit()
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .paperButtonFocusRing()
                        }
                    }

                    if !editAttachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(editAttachments) { att in
                                    ZStack(alignment: .topTrailing) {
                                        if let url = APIClient.shared.resolveMediaURL(att.thumbnailUrl ?? att.url) {
                                            CachedFilmImageView(url: url, maxHeight: 68)
                                                .frame(width: 68, height: 68)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                                                )
                                        }

                                        Button {
                                            editAttachments.removeAll(where: { $0.id == att.id })
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 15))
                                                .foregroundStyle(ArchivePalette.archivePaper, ArchivePalette.inkPrimary.opacity(0.85))
                                                .frame(width: 24, height: 24)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .paperButtonFocusRing(cornerRadius: 12)
                                        .accessibilityLabel("移除附件 \(att.originalFilename)")
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } else {
                        Text("可将照片拖拽至此，或按 ⌘V 直接粘贴剪贴板截图")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(.vertical, 4)
                    }
                }
                .padding(10)
                .background(ArchivePalette.archiveSubtle.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .strokeBorder(
                            isDropTargeted ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle,
                            style: StrokeStyle(lineWidth: isDropTargeted ? 1.2 : 0.5, dash: [4, 3])
                        )
                )

                // 6. 私密开关（统一使用纸本滑动开关 PaperSwitchToggleStyle）
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("仅自己可见（私密）")
                            .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("开启后展厅公开时不会展示此条记录，亦不写入系统 Spotlight")
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

                if let saveError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(saveError)
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .lineLimit(3)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .padding(8)
                    .background(ArchivePalette.accentWarm.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("保存失败：\(saveError)")
                }
            }
        }
        .onAppear {
            isContentFocused = true
        }
        .onDrop(of: [.image, .fileURL, .rawImage], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
        }
        .onPasteImageShortcut {
            pasteFromClipboard()
        }
    }

    private func save() async {
        guard !isSaving, !isUploading else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let cleanTitle = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = editContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(cleanTitle.isEmpty && cleanContent.isEmpty && editAttachments.isEmpty) else {
            saveError = "标题、正文与相纸不能同时为空"
            return
        }
        let cleanCity = editCityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLoc = editLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityCleared = cleanCity.isEmpty && editCityCode.isEmpty
        let code: String? = editCityCode.isEmpty ? nil : editCityCode
        let shouldClearAttachments = !entry.attachments.isEmpty && editAttachments.isEmpty
        let req = UpdateEntryRequest(
            type: editType.rawValue,
            title: cleanTitle,
            content: cleanContent,
            occurredAt: FormatUtils.beijingISOString(from: editOccurredAt),
            location: cleanLoc,
            cityCode: code,
            cityName: cleanCity,
            clearCity: cityCleared ? true : nil,
            isPrivate: editIsPrivate,
            attachmentIds: editAttachments.map(\.id),
            clearAttachments: shouldClearAttachments ? true : nil
        )
        do {
            try await onSave(req)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func selectPhotosForEdit() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .jpeg, .png, .heic, .rawImage]
        Task { @MainActor in
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = await panel.begin()
            }
            guard response == .OK, !panel.urls.isEmpty else { return }
            await uploadFileURLs(panel.urls)
        }
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        let box = DropLoader.makeProviderBox(providers)
        Task { @MainActor in
            let urls = await DropLoader.loadDroppablePhotoURLs(from: box)
            await uploadFileURLs(urls)
        }
        return true
    }

    private func pasteFromClipboard() {
        Task { @MainActor in
            let payload = await EntryPasteboard.readPayload()
            if !payload.fileURLs.isEmpty {
                await uploadFileURLs(payload.fileURLs)
                return
            }
            guard let data = payload.imageData else {
                saveError = "剪贴板中未检测到可用的图片或截图"
                return
            }
            isUploading = true
            saveError = nil
            defer { isUploading = false }
            do {
                let processed = try await ImageProcessor.processImageDataInBackground(
                    data,
                    originalFilename: "pasteboard-\(Int(Date().timeIntervalSince1970)).jpg"
                )
                let att = try await R2DirectUploader.shared.uploadProcessedPhoto(processed)
                editAttachments.append(att)
            } catch {
                saveError = "粘贴相纸上传失败：\(error.localizedDescription)"
            }
        }
    }

    private func uploadFileURLs(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isUploading = true
        saveError = nil
        var failures: [String] = []
        for url in urls {
            do {
                let processed = try await SandboxFileAccess.withAccess(to: url) { scopedURL in
                    try await ImageProcessor.processImageFileInBackground(at: scopedURL)
                }
                let att = try await R2DirectUploader.shared.uploadProcessedPhoto(processed)
                editAttachments.append(att)
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            saveError = failures.count == 1
                ? "相纸上传失败：\(failures[0])"
                : "\(failures.count) 张相纸上传失败：\(failures.prefix(2).joined(separator: "；"))"
        }
        isUploading = false
    }
}
