import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 全局统一三合一创作模态窗口 (NewEntryModal)
/// 优化：
/// 1. 响应式窗口高度（`minHeight: 460, idealHeight: 600, maxHeight: 680`），小屏不裁切
/// 2. 整窗支持拖放照片与聚焦输入框内 `⌘V` 直贴截图
/// 3. 造物手记改走 `SyncManager.shared.submitEntry` 离线发件箱闭环；乐观上屏完整透传 `attachments`
/// 4. 创作草稿持久化至 `0700` 受保护档案目录（`0600` 权限）并完整保存/恢复/重置 `isPrivate`
@MainActor
public struct NewEntryModal: View {
    @Bindable var appState: AppState
    var initialKind: String?
    var initialProjectId: Int?
    var initialCityCode: String?
    var initialCityName: String?
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public enum Kind: String, CaseIterable, Identifiable {
        case life = "life"
        case travel = "travel"
        case project = "project"

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .life: return "日常散页"
            case .travel: return "山川游历"
            case .project: return "造物手记"
            }
        }

        public var subtitle: String {
            switch self {
            case .life: return "身边小事、随笔思考与定格光影"
            case .travel: return "山川行迹与漫游记忆，点亮城市足迹图谱"
            case .project: return "为进行中或已归档的造物项目追加演进手记"
            }
        }

        public var icon: String {
            switch self {
            case .life: return "leaf"
            case .travel: return "airplane"
            case .project: return "hammer"
            }
        }
    }

    @State private var selectedKind: Kind = .life
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
        initialProjectId: Int? = nil,
        initialCityCode: String? = nil,
        initialCityName: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.appState = appState
        self.initialKind = initialKind
        self.initialProjectId = initialProjectId
        self.initialCityCode = initialCityCode
        self.initialCityName = initialCityName
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(selectedKind.subtitle)
                        .font(ArchiveTypography.editorialSerif(size: 12))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(.horizontal, 4)

                    Group {
                        switch selectedKind {
                        case .life:
                            EntryModalLifeForm(draft: draft, media: media)
                        case .travel:
                            EntryModalTravelForm(draft: draft, appState: appState, media: media)
                        case .project:
                            EntryModalProjectForm(draft: draft, appState: appState, media: media)
                        }
                    }
                    .id(selectedKind)
                    .transition(.opacity)
                }
                .padding(24)
            }

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

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
        .onChange(of: selectedKind) { _, newKind in
            switch newKind {
            case .travel:
                break
            case .life, .project:
                draft.selectedFootprintId = nil
            }
        }
        .onDisappear {
            if !didSubmitSuccessfully {
                saveDraft()
            }
        }
        .onPasteCommand(of: [.image, .fileURL]) { providers in
            media.paste(providers: providers)
        }
    }

    // MARK: - 顶栏与形态切换胶囊
    private var headerBar: some View {
        HStack(spacing: 0) {
            Text("记一笔")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .frame(width: 90, alignment: .leading)

            Spacer()

            HStack(spacing: 3) {
                ForEach(Kind.allCases) { kind in
                    let isSelected = (selectedKind == kind)
                    Button {
                        guard !isSelected else { return }
                        selectedKind = kind
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 10.5))
                            Text(kind.label)
                                .font(ArchiveTypography.bodySans(size: 12, weight: isSelected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(minHeight: ArchiveHitTarget.minPointer)
                        .background(isSelected ? ArchivePalette.archivePaper : Color.clear)
                        .foregroundStyle(isSelected ? ArchivePalette.inkPrimary : ArchivePalette.inkSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? ArchivePalette.borderSubtle : Color.clear, lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .paperButtonFocusRing(cornerRadius: 6)
                    .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: selectedKind)
                }
            }
            .padding(3)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            PaperIconButton(
                systemName: ArchiveIcon.close.systemName,
                label: "关闭创作弹窗",
                help: "关闭 (Esc)",
                size: 11,
                tint: ArchivePalette.inkSecondary
            ) {
                saveDraft()
                onDismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 底栏动作按钮
    private var footerActionBar: some View {
        VStack(spacing: 8) {
            if let err = displayErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
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
                .font(ArchiveTypography.bodySans(size: 11))
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: 3)
                .foregroundStyle(ArchivePalette.inkMuted)
            }

            Toggle(isOn: $draft.isPrivate) {
                HStack(spacing: 4) {
                    Image(systemName: draft.isPrivate ? "lock.fill" : "lock.open")
                        .font(.system(size: 10.5))
                        .foregroundStyle(draft.isPrivate ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                    Text("仅自己可见")
                        .font(ArchiveTypography.bodySans(size: 11.5))
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
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(isSubmitting ? "正在归册…" : submitButtonTitle)
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
            .disabled(isSubmitting || media.isUploading)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var submitButtonTitle: String {
        switch selectedKind {
        case .life: return "定格散页 (⌘↵)"
        case .travel: return "点亮游历 (⌘↵)"
        case .project: return draft.projectMode == "new" ? "立项造物 (⌘↵)" : "追加手记 (⌘↵)"
        }
    }

    private var displayErrorMessage: String? {
        errorMessage ?? media.errorMessage
    }

    // MARK: - 逻辑与提交
    private func setupInitialState() {
        if draft.newProjectCategory.isEmpty || draft.newProjectCategory == "开源造物" {
            draft.newProjectCategory = appState.projectCategories.first ?? "开源项目"
        }
        if let initK = initialKind, let k = Kind(rawValue: initK) {
            selectedKind = k
        }
        if let initProjId = initialProjectId {
            draft.selectedProjectId = initProjId
            draft.projectMode = "entry"
        } else if draft.selectedProjectId == nil && !appState.projects.isEmpty {
            draft.selectedProjectId = appState.projects.first?.id
        }
        if let cCode = initialCityCode, !cCode.isEmpty {
            draft.cityCode = cCode
            draft.cityName = initialCityName ?? ""
        } else if draft.cityCode.isEmpty {
            let profileCity = appState.profile.currentCity.trimmingCharacters(in: .whitespacesAndNewlines)
            if profileCity.isEmpty {
                draft.cityCode = ""
                draft.cityName = ""
            } else {
                draft.cityCode = FormatUtils.resolveCityCode(from: profileCity) ?? ""
                draft.cityName = profileCity
            }
        }
        restoreDraft()
    }

    private func handleSubmit() {
        errorMessage = nil
        isSubmitting = true

        Task { @MainActor in
            defer { isSubmitting = false }
            do {
                switch selectedKind {
                case .life:
                    try await submitLife()
                case .travel:
                    try await submitTravel()
                case .project:
                    try await submitProject()
                }
                clearDraft()
                didSubmitSuccessfully = true
                if appState.enablesHapticFeedback {
                    ArchiveFeedback.success()
                }
                if selectedKind == .project {
                    await appState.loadProjectsWishesFootprints()
                    await appState.loadEntries(forceFull: false)
                }
                await appState.loadConfigAndProfile()
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitLife() async throws {
        guard !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !media.uploadedAttachments.isEmpty else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "正文内容与相纸不能同时为空"])
        }
        _ = try await appState.submitQuickCapture(
            title: draft.effectiveTitle,
            content: draft.content,
            type: .life,
            location: nil,
            cityCode: draft.cityCode.isEmpty ? nil : draft.cityCode,
            cityName: draft.cityName.isEmpty ? nil : draft.cityName,
            footprintId: nil,
            attachmentIds: media.uploadedAttachments.map(\.id),
            attachments: media.uploadedAttachments,
            occurredAt: FormatUtils.beijingISOString(from: draft.occurredAt),
            isPrivate: draft.isPrivate
        )
    }

    private func submitTravel() async throws {
        guard !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.title.isEmpty || !media.uploadedAttachments.isEmpty else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "游历标题或内容不能为空"])
        }
        _ = try await appState.submitQuickCapture(
            title: draft.title.isEmpty ? (draft.cityName.isEmpty ? "游历手记" : "\(draft.cityName) · 游记") : draft.title,
            content: draft.content,
            type: .travel,
            location: nil,
            cityCode: draft.cityCode.isEmpty ? nil : draft.cityCode,
            cityName: draft.cityName.isEmpty ? nil : draft.cityName,
            footprintId: draft.selectedFootprintId,
            attachmentIds: media.uploadedAttachments.map(\.id),
            attachments: media.uploadedAttachments,
            occurredAt: FormatUtils.beijingISOString(from: draft.occurredAt),
            isPrivate: draft.isPrivate
        )
    }

    private func submitProject() async throws {
        if draft.projectMode == "new" {
            guard !draft.newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "项目名称不能为空"])
            }
            let req = CreateProjectRequest(
                title: draft.newProjectTitle,
                subtitle: draft.newProjectSubtitle.isEmpty ? nil : draft.newProjectSubtitle,
                description: draft.newProjectDesc.isEmpty ? draft.newProjectTitle : draft.newProjectDesc,
                category: draft.newProjectCategory.isEmpty ? nil : draft.newProjectCategory,
                status: draft.newProjectStatus,
                githubUrl: draft.newProjectGithub.isEmpty ? nil : draft.newProjectGithub,
                isPrivate: draft.isPrivate
            )
            _ = try await APIClient.shared.createProject(req)
        } else {
            guard !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "进展手记正文不能为空"])
            }
            let req = CreateEntryRequest(
                type: "project",
                title: draft.title,
                content: draft.content,
                occurredAt: FormatUtils.beijingISOString(from: draft.occurredAt),
                location: nil,
                cityCode: draft.cityCode.isEmpty ? nil : draft.cityCode,
                cityName: draft.cityName.isEmpty ? nil : draft.cityName,
                projectId: draft.selectedProjectId,
                wishId: nil,
                footprintId: nil,
                isPrivate: draft.isPrivate,
                attachmentIds: media.uploadedAttachments.map(\.id)
            )
            let (_, queuedOffline) = try await SyncManager.shared.submitEntry(req, attachments: media.uploadedAttachments)
            if queuedOffline {
                appState.showTemporaryBanner("造物手记已暂存至本地发件箱，网络恢复后自动同步")
            } else {
                appState.showTemporaryBanner("已追加造物进展手记")
            }
        }
    }

    // MARK: - 受保护草稿持久化 (`0600` 文件权限 + `isPrivate` 闭环)
    private func saveDraft() {
        guard !draft.title.isEmpty || !draft.content.isEmpty else { return }
        var dict: [String: Any] = [
            "kind": selectedKind.rawValue,
            "title": draft.title,
            "content": draft.content,
            "cityCode": draft.cityCode,
            "cityName": draft.cityName,
            "isPrivate": draft.isPrivate
        ]
        if let projectId = draft.selectedProjectId {
            dict["projectId"] = projectId
        }
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

        if initialKind == nil,
           let k = dict["kind"] as? String,
           let kind = Kind(rawValue: k) {
            selectedKind = kind
        }
        if initialProjectId == nil, let pid = dict["projectId"] as? Int {
            draft.selectedProjectId = pid
        }
        if let t = dict["title"] as? String { draft.title = t }
        if let c = dict["content"] as? String { draft.content = c }
        if let priv = dict["isPrivate"] as? Bool { draft.isPrivate = priv }
        if initialCityCode == nil || initialCityCode?.isEmpty == true {
            if let code = dict["cityCode"] as? String { draft.cityCode = code }
            if let name = dict["cityName"] as? String { draft.cityName = name }
        }
    }

    private func clearDraft() {
        try? FileManager.default.removeItem(at: draftFileURL)
        UserDefaults.standard.removeObject(forKey: legacyDraftDefaultsKey)
        draft.title = ""
        draft.content = ""
        draft.isPrivate = false
        media.removeAll()
    }

    private func hasSavedDraft() -> Bool {
        FileManager.default.fileExists(atPath: draftFileURL.path)
            || UserDefaults.standard.data(forKey: legacyDraftDefaultsKey) != nil
    }
}
