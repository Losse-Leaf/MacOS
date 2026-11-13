import SwiftUI
import AppKit

/// 修改散页手稿弹窗表单 (EditEntrySheetView)
@MainActor
public struct EditEntrySheetView: View {
    public let entry: LifeEntry
    /// 异步抛错：保存失败必须留在弹窗里显示原因，不能静默关闭。
    public var onSave: @MainActor (UpdateEntryRequest) async throws -> Void
    public var onCancel: () -> Void

    @State private var editType: EntryType
    @State private var editOccurredAt: Date
    @State private var editTitle: String
    @State private var editContent: String
    @State private var editCityCode: String
    @State private var editCityName: String
    @State private var editAttachments: [Attachment]
    @State private var editIsPrivate: Bool
    @State private var isUploading: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?

    public init(
        entry: LifeEntry,
        onSave: @escaping @MainActor (UpdateEntryRequest) async throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onCancel = onCancel
        _editType = State(initialValue: EntryType(rawValue: entry.type) ?? .life)
        _editOccurredAt = State(initialValue: FormatUtils.parseFlexDate(entry.occurredAt) ?? Date())
        _editTitle = State(initialValue: entry.title)
        _editContent = State(initialValue: entry.content)
        _editCityCode = State(initialValue: entry.cityCode ?? "")
        _editCityName = State(initialValue: entry.cityName ?? entry.location ?? "")
        _editAttachments = State(initialValue: entry.attachments)
        _editIsPrivate = State(initialValue: entry.isPrivate)
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "编辑生活手稿",
            width: ArchiveSheetWidth.standard,
            isSubmitting: isSaving,
            submitTitle: "保存修改",
            onCancel: onCancel,
            onSubmit: { Task { await save() } }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // 手稿类型切换
                HStack(spacing: 6) {
                    Text("类型：")
                        .font(ArchiveTypography.monoScale(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    ForEach(EntryType.allCases) { t in
                        PaperPillButton(
                            title: t.label,
                            isSelected: editType == t
                        ) {
                            editType = t
                        }
                    }
                }

                // 发生时刻
                PaperDatePicker(selection: $editOccurredAt, enableTime: true, label: "发生时刻：")

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
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 13))
                    .lineLimit(8, reservesSpace: true)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                    )

                PaperCityPicker(selectedCode: $editCityCode, selectedName: $editCityName, placeholder: "选择城市…")

                // 照片相纸附件管理与增删
                VStack(alignment: .leading, spacing: 6) {
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
                        Button("+ 补选相纸照片") {
                            selectPhotosForEdit()
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .paperButtonFocusRing()
                        .controlSize(.small)
                    }
                }

                if !editAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(editAttachments) { att in
                                ZStack(alignment: .topTrailing) {
                                    if let url = APIClient.shared.resolveMediaURL(att.url) {
                                        // 关键：AsyncImage 不走 PaperImageCache，也不做降采样，
                                        // 一张 4K 原图会在 68×68 的方框里解码出约 39MB 位图。
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
                                    }
                                    .buttonStyle(.plain)
                                    .padding(2)
                                    .accessibilityLabel("移除附件 \(att.originalFilename)")
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

                Toggle(isOn: $editIsPrivate) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("仅自己可见（私密）")
                            .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("开启后展厅公开时不会展示此条记录")
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(ArchivePalette.inkPrimary)
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
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let cleanTitle = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = editContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(cleanTitle.isEmpty && cleanContent.isEmpty) else {
            saveError = "标题与正文不能同时为空"
            return
        }
        let cleanCity = editCityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityCleared = cleanCity.isEmpty && editCityCode.isEmpty
        let code: String? = editCityCode.isEmpty ? nil : editCityCode
        let req = UpdateEntryRequest(
            type: editType.rawValue,
            title: cleanTitle,
            // 空串是显式清空；nil 会被后端当作保持原值。
            content: cleanContent,
            occurredAt: FormatUtils.beijingISOString(from: editOccurredAt),
            location: cleanCity,
            cityCode: code,
            cityName: cleanCity,
            clearCity: cityCleared ? true : nil,
            isPrivate: editIsPrivate,
            attachmentIds: editAttachments.map(\.id)
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
        panel.allowedContentTypes = [.image, .rawImage]
        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            Task { @MainActor in
                isUploading = true
                saveError = nil
                var failures: [String] = []
                for url in urls {
                    do {
                        // 沙箱：NSOpenPanel 选中的文件位于沙箱容器之外，
                        // 必须取得安全作用域授权才能读取，否则读取会静默失败。
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
    }
}
