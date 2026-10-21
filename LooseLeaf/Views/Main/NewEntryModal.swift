import SwiftUI
import AppKit

/// 全局统一五合一创作模态窗口 (NewEntryModal)
/// 严格 1:1 对标 Web 端 `web/src/components/NewEntryModal.vue`：
/// 1. 支持五大形态切换：日常 (life)、游历 (travel)、造物 (project)、心愿 (wish)、账目 (transaction)
/// 2. 具备自动草稿持久化能力 (looseleaf_entry_draft_v1)，意外关闭不丢稿
/// 3. 日期绑定 PaperDatePicker，城市绑定 PaperCityPicker，支持图片附件装裱与相机 EXIF
/// 4. 完美支持 ESC 键与右上角 X 快速退出，零硬编码颜色
///
/// **架构说明（性能重构）**：
/// 本 View 只负责「形态选择 + 附件区 + 底部操作栏 + 错误条 + 提交逻辑」；
/// 五个形态的表单各自是独立子 View（`EntryModalLifeForm` 等），只挂载当前选中的那一个。
/// 表单字段统一放在 `EntryDraft` (@Observable) 里由父子共享对象引用，
/// 因此在任意输入框里敲一个字，都只会重绘**读取了该字段的那个子 View**，
/// 父 body 与其它四个分支完全不再参与求值 —— 这正是「点击修改卡片或者创建内容很卡」的根治点。
@MainActor
public struct NewEntryModal: View {
    @Bindable var appState: AppState
    var initialKind: String?
    var initialProjectId: Int?
    var initialCityCode: String?
    var initialCityName: String?
    var onDismiss: () -> Void

    public enum Kind: String, CaseIterable, Identifiable {
        case life = "life"
        case travel = "travel"
        case project = "project"
        case wish = "wish"
        case transaction = "transaction"

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .life: return "日常"
            case .travel: return "游历"
            case .project: return "造物"
            case .wish: return "心愿"
            case .transaction: return "账目"
            }
        }

        public var subtitle: String {
            switch self {
            case .life: return "身边小事、随笔思考与定格光影"
            case .travel: return "山川行迹与漫游记忆，点亮城市足迹图谱"
            case .project: return "立项新造物或为进行中的项目追加手记"
            case .wish: return "许下好物器物、远方旅程或人生里程碑"
            case .transaction: return "记录日常收支、旅行花销、信贷分期或固定资产"
            }
        }

        public var icon: String {
            switch self {
            case .life: return "leaf"
            case .travel: return "airplane"
            case .project: return "hammer"
            case .wish: return "sparkles"
            case .transaction: return "creditcard"
            }
        }
    }

    @State private var selectedKind: Kind = .life
    @State private var isSubmitting: Bool = false
    @State private var didSubmitSuccessfully: Bool = false
    @State private var errorMessage: String?

    /// 表单草稿容器：五个形态子 View 与父 View 共享同一份数据源（对象引用，非回调）
    @State private var draft = EntryDraft()
    /// 相纸装裱容器：逐张进度、失败重试与附件汇总都在这里收敛
    @State private var media = EntryMediaState()

    private let draftStorageKey = "looseleaf_entry_draft_v1"

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
                    // 形态引导副标题
                    Text(selectedKind.subtitle)
                        .font(ArchiveTypography.editorialSerif(size: 12))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .padding(.horizontal, 4)

                    // 表单主体切换：五个分支各自是独立子 View，只有选中的那一个会被挂载
                    Group {
                        switch selectedKind {
                        case .life:
                            EntryModalLifeForm(draft: draft, media: media)
                        case .travel:
                            EntryModalTravelForm(draft: draft, appState: appState, media: media)
                        case .project:
                            EntryModalProjectForm(draft: draft, appState: appState, media: media)
                        case .wish:
                            EntryModalWishForm(draft: draft, media: media)
                        case .transaction:
                            EntryModalTransactionForm(draft: draft, appState: appState)
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
        .frame(width: 720, height: 600)
        .background(ArchivePalette.archivePaper)
        .onAppear {
            setupInitialState()
        }
        .onDisappear {
            // 点击遮罩 / ESC / 切窗关闭都要保住草稿；成功提交后由 clearDraft 收尾
            if !didSubmitSuccessfully {
                saveDraft()
            }
        }
        // ⌘V 粘贴相纸：截图或访达拷贝的图片文件都能直接装裱
        .onPasteCommand(of: [.image, .fileURL]) { providers in
            handlePasteCommand(providers)
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

            // 居中五形态胶囊
            HStack(spacing: 3) {
                ForEach(Kind.allCases) { kind in
                    Button {
                        guard selectedKind != kind else { return }
                        selectedKind = kind
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 10.5))
                            Text(kind.label)
                                .font(ArchiveTypography.bodySans(size: 12, weight: selectedKind == kind ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedKind == kind ? ArchivePalette.archivePaper : Color.clear)
                        .foregroundStyle(selectedKind == kind ? ArchivePalette.inkPrimary : ArchivePalette.inkSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedKind == kind ? ArchivePalette.borderSubtle : Color.clear, lineWidth: 0.5)
                        )
                        .shadow(color: selectedKind == kind ? Color.black.opacity(0.04) : Color.clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.12), value: selectedKind)
                }
            }
            .padding(3)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // 右上角退出按钮
            Button {
                saveDraft()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .frame(width: 26, height: 26)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("关闭 (Esc)")
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 底栏动作按钮
    private var footerActionBar: some View {
        VStack(spacing: 8) {
            // 错误提示固定在操作栏正上方：原先放在表单顶部，长表单提交失败时错误在屏幕外
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

            // 上传中提示：附件没传完就不许提交，必须让用户看得见
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
        HStack {
            if hasSavedDraft() {
                Button("清空草稿") {
                    clearDraft()
                }
                .font(ArchiveTypography.bodySans(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(ArchivePalette.inkMuted)
            }

            Spacer()

            Button("取消") {
                saveDraft()
                onDismiss()
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

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
            // 上传中禁止提交：否则 attachments 还没 append 完就提交，图片成为孤儿。
            .disabled(isSubmitting || media.isUploading)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    /// 提交按钮文案
    private var submitButtonTitle: String {
        switch selectedKind {
        case .life: return "定格散页 (⌘↵)"
        case .travel: return "点亮游历 (⌘↵)"
        case .project: return draft.projectMode == "new" ? "立项造物 (⌘↵)" : "追加手记 (⌘↵)"
        case .wish: return "许下心愿 (⌘↵)"
        case .transaction: return "记下这笔账 (⌘↵)"
        }
    }

    /// 错误提示来源：提交错误优先，其次是相纸装裱失败汇总
    private var displayErrorMessage: String? {
        errorMessage ?? media.errorMessage
    }

    // MARK: - 逻辑与提交
    private func setupInitialState() {
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
            // 关键：城市代码与名称必须来自**同一个**来源。
            // 原先这里硬编码 cityCode = "330100"（浙江杭州），却把名称设成用户的所在城市，
            // 于是选择器显示成「浙江 · 宜宾市」这种 province 与 city 错配的组合。
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
                case .wish:
                    try await submitWish()
                case .transaction:
                    try await submitTransaction()
                }
                clearDraft()
                didSubmitSuccessfully = true
                if appState.enablesHapticFeedback {
                    ArchiveFeedback.success()
                }
                // 只有 life / travel 走 submitQuickCapture 的乐观写入；
                // project / wish / transaction 在此处直接调 API，必须把对应领域重新拉一次，
                // 否则用户刚创建的项目/心愿/账目不会出现在界面上（直到下一次全量同步）。
                switch selectedKind {
                case .life, .travel:
                    break
                case .project:
                    await appState.loadProjectsWishesFootprints()
                    if draft.projectMode == "entry" {
                        await appState.loadEntries(forceFull: false)
                    }
                case .wish:
                    await appState.loadProjectsWishesFootprints()
                case .transaction:
                    await appState.loadTransactionsAndAssets(forceFull: false)
                }
                await appState.loadConfigAndProfile()
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitLife() async throws {
        guard !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "正文内容不能为空"])
        }
        _ = try await appState.submitQuickCapture(
            // 朋友圈式：日常不单列标题，标题由正文第一行派生
            title: draft.effectiveTitle,
            content: draft.content,
            type: .life,
            location: nil,
            cityCode: draft.cityCode.isEmpty ? nil : draft.cityCode,
            cityName: draft.cityName.isEmpty ? nil : draft.cityName,
            attachmentIds: media.uploadedAttachments.map(\.id),
            featured: draft.isFeatured,
            occurredAt: FormatUtils.beijingISOString(from: draft.occurredAt)
        )
    }

    private func submitTravel() async throws {
        guard !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.title.isEmpty else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "游历标题或内容不能为空"])
        }
        _ = try await appState.submitQuickCapture(
            title: draft.title.isEmpty ? "\(draft.cityName) · 游记" : draft.title,
            content: draft.content,
            type: .travel,
            location: nil,
            cityCode: draft.cityCode.isEmpty ? nil : draft.cityCode,
            cityName: draft.cityName.isEmpty ? nil : draft.cityName,
            attachmentIds: media.uploadedAttachments.map(\.id),
            featured: true,
            occurredAt: FormatUtils.beijingISOString(from: draft.occurredAt)
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
                githubUrl: draft.newProjectGithub.isEmpty ? nil : draft.newProjectGithub
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
                featured: false,
                cityCode: draft.cityCode.isEmpty ? nil : draft.cityCode,
                cityName: draft.cityName.isEmpty ? nil : draft.cityName,
                projectId: draft.selectedProjectId,
                wishId: nil,
                footprintId: nil,
                attachmentIds: media.uploadedAttachments.map(\.id)
            )
            _ = try await APIClient.shared.createEntry(req)
        }
    }

    private func submitWish() async throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "心愿名称不能为空"])
        }
        let budgetCents = FormatUtils.parseYuanToCents(draft.wishBudgetYuan) ?? 0
        let finalSpec = draft.wishKind == "item" ? (draft.wishSpec.isEmpty ? nil : draft.wishSpec) : nil
        let finalCityCode = draft.wishKind == "travel" ? (draft.wishCityCode.isEmpty ? nil : draft.wishCityCode) : nil
        let finalCityName = draft.wishKind == "travel" ? (draft.wishCityName.isEmpty ? nil : draft.wishCityName) : nil

        let req = CreateWishRequest(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: draft.wishKind,
            note: draft.content.isEmpty ? nil : draft.content,
            spec: finalSpec,
            cityCode: finalCityCode,
            cityName: finalCityName,
            budget: budgetCents,
            targetDate: FormatUtils.beijingDateString(from: draft.wishTargetDate),
            attachmentIds: media.uploadedAttachments.map(\.id)
        )
        _ = try await APIClient.shared.createWish(req)
    }

    private func submitTransaction() async throws {
        guard let cents = FormatUtils.parseYuanToCents(draft.txAmountYuan), cents > 0 else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "请输入有效金额"])
        }
        let isExp = draft.txType == "expense"
        let installmentPay: Int64? = (isExp && draft.isInstallment && draft.installmentMonths > 0) ? (cents / Int64(draft.installmentMonths)) : nil

        let req = CreateTransactionRequest(
            amount: cents,
            type: draft.txType,
            category: draft.txCategory,
            title: draft.content.isEmpty ? draft.txCategory : draft.content,
            note: draft.content.isEmpty ? nil : draft.content,
            paymentMethod: draft.txPaymentMethod,
            wishId: draft.selectedWishId,
            footprintId: draft.selectedFootprintId,
            cityCode: draft.cityCode.isEmpty ? nil : draft.cityCode,
            occurredAt: FormatUtils.beijingISOString(from: draft.occurredAt),
            isInstallment: isExp && draft.isInstallment,
            installmentChannelCode: (isExp && draft.isInstallment) ? draft.installmentChannel : nil,
            installmentTotalAmount: (isExp && draft.isInstallment) ? cents : nil,
            installmentMonths: (isExp && draft.isInstallment) ? draft.installmentMonths : nil,
            installmentMonthlyPay: installmentPay,
            installmentRemainMonths: (isExp && draft.isInstallment) ? draft.installmentMonths : nil,
            repaymentDay: (isExp && draft.isInstallment) ? draft.customRepaymentDay : nil,
            linkGearAsset: isExp && draft.syncToGear,
            gearCategory: (isExp && draft.syncToGear) ? draft.gearCategory : nil,
            gearSpec: (isExp && draft.syncToGear) ? (draft.gearSpec.isEmpty ? nil : draft.gearSpec) : nil
        )
        // 走 SyncManager 而不是直连 API：离线时进入持久化 Outbox，
        // 并复用其乐观插入与重试逻辑（此前离线提交会直接失败）。
        _ = try await SyncManager.shared.submitTransaction(req)
    }

    // MARK: - 粘贴装裱

    /// ⌘V 粘贴装裱：读取系统剪贴板中的图片文件 URL 或图片二进制数据，
    /// 剪贴板里没有可用图片时回退到 SwiftUI 提供的 provider 管线。
    private func handlePasteCommand(_ providers: [NSItemProvider]) {
        media.paste(providers: providers)
    }

    // MARK: - 草稿持久化
    private func saveDraft() {
        guard !draft.title.isEmpty || !draft.content.isEmpty else { return }
        let dict: [String: Any] = [
            "kind": selectedKind.rawValue,
            "title": draft.title,
            "content": draft.content,
            "cityCode": draft.cityCode,
            "cityName": draft.cityName,
            "isFeatured": draft.isFeatured
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: draftStorageKey)
        }
    }

    private func restoreDraft() {
        guard let data = UserDefaults.standard.data(forKey: draftStorageKey),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        // 关键：调用方显式指定的形态 / 项目 / 城市优先于草稿。
        // 原先草稿无条件覆盖 selectedKind，导致用户从「造物」入口打开却落到「日常」。
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
        if initialCityCode == nil || initialCityCode?.isEmpty == true {
            if let code = dict["cityCode"] as? String { draft.cityCode = code }
            if let name = dict["cityName"] as? String { draft.cityName = name }
        }
        if let feat = dict["isFeatured"] as? Bool { draft.isFeatured = feat }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
        draft.title = ""
        draft.content = ""
        draft.isFeatured = false
        media.removeAll()
    }

    private func hasSavedDraft() -> Bool {
        UserDefaults.standard.data(forKey: draftStorageKey) != nil
    }
}
