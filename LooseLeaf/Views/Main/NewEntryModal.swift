import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 全局散页创作模态窗口 (NewEntryModal)
/// 职责：定格日常散页手稿与相纸装裱
@MainActor
public struct NewEntryModal: View {
    @Bindable var appState: AppState
    var initialKind: String?
    var onDismiss: () -> Void

    @State private var isSubmitting: Bool = false
    @State private var didSubmitSuccessfully: Bool = false
    @State private var isModalDropTargeted: Bool = false
    @State private var errorMessage: String?

    @State private var draft = EntryDraft()
    @State private var media = EntryMediaState()

    private let legacyDraftDefaultsKey = "looseleaf_entry_draft_v1"
    private var draftFileURL: URL {
        SyncManager.sharedStorageDirectory.appendingPathComponent("entry_draft_v1.json")
    }

    public init(
        appState: AppState,
        initialKind: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.appState = appState
        self.initialKind = initialKind
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EntryModalLifeForm(draft: draft, media: media)
                }
                .padding(24)
            }

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))

            footerActionBar
        }
        .frame(minWidth: 580, idealWidth: 720, maxWidth: 720)
        .frame(minHeight: 460, idealHeight: 600, maxHeight: 680)
        .background(ArchivePalette.archivePaper)
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.lg)
                .strokeBorder(
                    isModalDropTargeted ? ArchivePalette.accentWarm : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .allowsHitTesting(false)
        )
        .onDrop(of: [.image, .fileURL, .rawImage], isTargeted: $isModalDropTargeted) { providers in
            media.handleDrop(providers: providers)
        }
        .onPasteImageShortcut {
            media.paste(providers: [])
        }
        .onAppear {
            setupInitialState()
        }
        .onDisappear {
            if !didSubmitSuccessfully {
                saveDraft()
            }
        }
        .onPasteCommand(of: [.image, .fileURL]) { providers in
            media.paste(providers: providers)
        }
        .interactiveDismissDisabled(media.isUploading || isSubmitting)
    }

    // MARK: - 顶栏
    private var headerBar: some View {
        HStack(spacing: 0) {
            Text("写散页")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Spacer()

            PaperIconButton(
                systemName: ArchiveIcon.close.systemName,
                label: "关闭创作弹窗",
                help: "关闭 (Esc)",
                size: ArchiveTypography.Scale.caption,
                tint: ArchivePalette.inkSecondary
            ) {
                saveDraft()
                onDismiss()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - 底栏动作按钮
    private var footerActionBar: some View {
        VStack(spacing: 8) {
            if let err = displayErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.caption))
                    Text(err)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ArchivePalette.accentWarm)
                .padding(8)
                .background(ArchivePalette.accentWarm.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                .accessibilityLabel("错误：\(err)")
            }

            if media.isUploading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("相纸正在装裱（\(media.succeededCount)/\(media.items.count)），装裱完成后即可提交")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ArchivePalette.inkSecondary)
                .accessibilityLabel("相纸正在装裱，暂不可提交")
            }

            footerButtons
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {
            if hasSavedDraft() {
                Button("清空草稿") {
                    clearDraft()
                }
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: 3)
                .foregroundStyle(ArchivePalette.inkMuted)
            }

            Toggle(isOn: $draft.isPrivate) {
                HStack(spacing: 4) {
                    Image(systemName: draft.isPrivate ? "lock.fill" : "lock.open")
                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.label))
                        .foregroundStyle(draft.isPrivate ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                    Text("仅自己可见")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.footnote))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                }
            }
            .toggleStyle(.paperSwitch)

            Spacer()

            Button("取消") {
                saveDraft()
                onDismiss()
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            .paperButtonFocusRing()

            Button {
                handleSubmit()
            } label: {
                HStack(spacing: 5) {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.micro, weight: .semibold))
                    }
                    Text(isSubmitting ? "正在归册…" : "定格散页 (⌘↵)")
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
            .disabled(isSubmitting || media.isUploading)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var displayErrorMessage: String? {
        errorMessage ?? media.errorMessage
    }

    // MARK: - 逻辑与提交
    private func setupInitialState() {
        if draft.location.isEmpty {
            let profileCity = appState.profile.currentCity.trimmingCharacters(in: .whitespacesAndNewlines)
            if !profileCity.isEmpty {
                draft.location = profileCity
                // 个人资料城市仅作默认占位，若装入含 GPS EXIF 的照片仍优先填充拍摄地点
                draft.userEditedLocation = false
            }
        }
        restoreDraft()
        media.onPhotoMetadataExtracted = { capturedAt, lat, lon in
            if let capturedAt, !draft.userEditedTime, let date = FormatUtils.parseFlexDate(capturedAt) {
                draft.occurredAt = date
            }
            if let lat, let lon, (!draft.userEditedLocation || draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                Task { @MainActor in
                    if let resolved = await ImageProcessor.reverseGeocodeLocation(latitude: lat, longitude: lon),
                       (!draft.userEditedLocation || draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        draft.location = resolved
                    }
                }
            }
        }
    }

    private func handleSubmit() {
        errorMessage = nil
        isSubmitting = true

        Task { @MainActor in
            defer { isSubmitting = false }
            do {
                try await submitLife()
                clearDraft()
                didSubmitSuccessfully = true
                if appState.enablesHapticFeedback {
                    ArchiveFeedback.success()
                }
                await appState.loadConfigAndProfile()
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitLife() async throws {
        let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty || !cleanContent.isEmpty || !media.uploadedAttachments.isEmpty else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "标题、正文与相纸不能同时为空"])
        }
        let cleanLocation = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await appState.submitQuickCapture(
            title: draft.effectiveTitle,
            content: draft.content,
            type: .life,
            category: draft.category,
            location: cleanLocation.isEmpty ? nil : cleanLocation,
            attachmentIds: media.uploadedAttachments.map(\.id),
            attachments: media.uploadedAttachments,
            occurredAt: FormatUtils.beijingISOString(from: draft.occurredAt),
            isPrivate: draft.isPrivate
        )
    }

    // MARK: - 受保护草稿持久化 (`0600` 文件权限 + `isPrivate` 闭环)
    private func saveDraft() {
        guard !draft.title.isEmpty || !draft.content.isEmpty || draft.category != .daily else { return }
        let dict: [String: Any] = [
            "category": draft.category.rawValue,
            "title": draft.title,
            "content": draft.content,
            "location": draft.location,
            "isPrivate": draft.isPrivate
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: draftFileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: draftFileURL.path)
            UserDefaults.standard.removeObject(forKey: legacyDraftDefaultsKey)
        }
    }

    private func restoreDraft() {
        let data: Data?
        if let fileData = try? Data(contentsOf: draftFileURL) {
            data = fileData
        } else if let legacyData = UserDefaults.standard.data(forKey: legacyDraftDefaultsKey) {
            data = legacyData
            UserDefaults.standard.removeObject(forKey: legacyDraftDefaultsKey)
        } else {
            data = nil
        }
        guard let data,
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

        if let rawCat = dict["category"] as? String { draft.category = EntryCategory(normalized: rawCat) }
        if let t = dict["title"] as? String { draft.title = t }
        if let c = dict["content"] as? String { draft.content = c }
        if let loc = dict["location"] as? String, !loc.isEmpty { draft.location = loc }
        if let priv = dict["isPrivate"] as? Bool { draft.isPrivate = priv }
    }

    private func clearDraft() {
        try? FileManager.default.removeItem(at: draftFileURL)
        UserDefaults.standard.removeObject(forKey: legacyDraftDefaultsKey)
        draft.category = .daily
        draft.title = ""
        draft.content = ""
        draft.location = ""
        draft.isPrivate = false
        media.removeAll()
    }

    private func hasSavedDraft() -> Bool {
        FileManager.default.fileExists(atPath: draftFileURL.path)
            || UserDefaults.standard.data(forKey: legacyDraftDefaultsKey) != nil
    }
}
