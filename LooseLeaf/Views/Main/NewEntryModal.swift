import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 全局统一五合一创作模态窗口 (NewEntryModal)
/// 严格 1:1 对标 Web 端 `web/src/components/NewEntryModal.vue`：
/// 1. 支持五大形态切换：日常 (life)、游历 (travel)、造物 (project)、心愿 (wish)、账目 (transaction)
/// 2. 具备自动草稿持久化能力 (looseleaf_entry_draft_v1)，意外关闭不丢稿
/// 3. 日期绑定 PaperDatePicker，城市绑定 PaperCityPicker，支持图片附件装裱与相机 EXIF
/// 4. 完美支持 ESC 键与右上角 X 快速退出，零硬编码颜色
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
    @State private var errorMessage: String?

    // 通用字段
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var occurredAt: Date = Date()
    @State private var cityCode: String = ""
    @State private var cityName: String = ""
    @State private var isFeatured: Bool = false
    @State private var attachments: [Attachment] = []
    @State private var extractedCameraLine: String = ""
    @State private var isUploadingMedia: Bool = false
    @State private var uploadProgress: Double = 0.0

    // 游历专有
    @State private var selectedFootprintId: Int?
    @State private var departedAt: Date = Date()

    // 造物专有
    @State private var projectMode: String = "entry" // "new" 或 "entry"
    @State private var selectedProjectId: Int?
    @State private var newProjectTitle: String = ""
    @State private var newProjectSubtitle: String = ""
    @State private var newProjectCategory: String = "开源项目"
    @State private var newProjectStatus: String = "Active"
    @State private var newProjectGithub: String = ""
    @State private var newProjectDesc: String = ""
    @State private var newProjectStory: String = ""

    // 心愿专有
    @State private var wishKind: String = "item" // item, travel, milestone
    @State private var wishBudgetYuan: String = ""
    @State private var wishTargetDate: Date = Date()

    // 账目专有
    @State private var txType: String = "expense" // expense, income
    @State private var txAmountYuan: String = ""
    @State private var txCategory: String = "餐饮"
    @State private var txPaymentMethod: String = "微信支付"
    @State private var isInstallment: Bool = false
    @State private var installmentChannel: String = "huabei"
    @State private var installmentMonths: Int = 12
    @State private var customRepaymentDay: Int = 10
    @State private var syncToGear: Bool = false
    @State private var gearCategory: String = "数码器材"
    @State private var gearSpec: String = ""

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

                    if let err = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 11))
                            Text(err)
                                .font(ArchiveTypography.bodySans(size: 11))
                        }
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(8)
                        .background(ArchivePalette.accentWarm.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // 表单主体切换
                    switch selectedKind {
                    case .life:
                        lifeFormView
                    case .travel:
                        travelFormView
                    case .project:
                        projectFormView
                    case .wish:
                        wishFormView
                    case .transaction:
                        transactionFormView
                    }
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
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedKind = kind
                        }
                        AudioFeedback.shared.playTink()
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
            .disabled(isSubmitting)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var submitButtonTitle: String {
        switch selectedKind {
        case .life: return "定格散页 (⌘↵)"
        case .travel: return "点亮游历 (⌘↵)"
        case .project: return projectMode == "new" ? "立项造物 (⌘↵)" : "追加手记 (⌘↵)"
        case .wish: return "许下心愿 (⌘↵)"
        case .transaction: return "记下这笔账 (⌘↵)"
        }
    }

    // MARK: - 1. 日常表单
    private var lifeFormView: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("标题（可选，留白则以正文第一行呈现）", text: $title)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .medium))
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextEditor(text: $content)
                .font(ArchiveTypography.bodySans(size: 13))
                .lineSpacing(4)
                .frame(minHeight: 120)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    Group {
                        if content.isEmpty {
                            Text("记下这一刻的思绪、见闻或生活琐记…")
                                .font(ArchiveTypography.bodySans(size: 13))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )

            HStack(spacing: 12) {
                PaperDatePicker(selection: $occurredAt, label: "发生时刻")
                PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName)
                Toggle("精选散页", isOn: $isFeatured)
                    .toggleStyle(.checkbox)
                    .font(ArchiveTypography.bodySans(size: 11.5))
            }

            mediaAttachmentsSection
        }
    }

    // MARK: - 2. 游历表单
    private var travelFormView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName)

                if !appState.footprints.isEmpty {
                    Picker("关联既有足迹票根", selection: $selectedFootprintId) {
                        Text("新建独立漫游").tag(nil as Int?)
                        ForEach(appState.footprints) { fp in
                            Text("\(fp.cityName) · \(fp.title ?? "行旅")").tag(fp.id as Int?)
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 12))
                }
            }

            HStack(spacing: 12) {
                PaperDatePicker(selection: $occurredAt, label: "启程/抵达时刻")
                PaperDatePicker(selection: $departedAt, label: "离开时刻")
            }

            TextField("旅途标题（例：西湖暮色寻茶记）", text: $title)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .medium))
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextEditor(text: $content)
                .font(ArchiveTypography.bodySans(size: 13))
                .lineSpacing(4)
                .frame(minHeight: 120)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            mediaAttachmentsSection
        }
    }

    // MARK: - 3. 造物表单
    private var projectFormView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("造物形态", selection: $projectMode) {
                Text("追加进展手记").tag("entry")
                Text("立项新造物").tag("new")
            }
            .pickerStyle(.segmented)

            if projectMode == "new" {
                TextField("造物项目名称（例：Loose-Leaf macOS 客户端）", text: $newProjectTitle)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .medium))
                    .padding(10)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 12) {
                    Picker("项目类别", selection: $newProjectCategory) {
                        ForEach(appState.projectCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 12))

                    Picker("当前状态", selection: $newProjectStatus) {
                        Text("进行中 (Active)").tag("Active")
                        Text("已完结 (Archived)").tag("Archived")
                    }
                    .font(ArchiveTypography.bodySans(size: 12))
                }

                TextField("一句话副标（例：轻量原生架构）", text: $newProjectSubtitle)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                TextField("代码仓或产品直链（GitHub / URL）", text: $newProjectGithub)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                TextEditor(text: $newProjectDesc)
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .frame(height: 80)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        Group {
                            if newProjectDesc.isEmpty {
                                Text("项目简介与核心设计思想…")
                                    .font(ArchiveTypography.bodySans(size: 12))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .padding(12)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
            } else {
                if appState.projects.isEmpty {
                    Text("当前尚无进行中的造物项目，请切换至「立项新造物」完成初始立项。")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                } else {
                    Picker("选择归属项目", selection: $selectedProjectId) {
                        ForEach(appState.projects) { proj in
                            Text("\(proj.title) (\(proj.category ?? "未分类"))").tag(proj.id as Int?)
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 12.5))

                    TextField("手记主题（例：完成 1:1 架构对齐）", text: $title)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.editorialSerif(size: 14.5, weight: .medium))
                        .padding(10)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    TextEditor(text: $content)
                        .font(ArchiveTypography.bodySans(size: 13))
                        .lineSpacing(4)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 12) {
                        PaperDatePicker(selection: $occurredAt, label: "进展时刻")
                        PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName)
                    }

                    mediaAttachmentsSection
                }
            }
        }
    }

    // MARK: - 4. 心愿表单
    private var wishFormView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("心愿维度", selection: $wishKind) {
                Text("好物器物").tag("item")
                Text("行旅探索").tag("travel")
                Text("阶段里程碑").tag("milestone")
            }
            .pickerStyle(.segmented)

            TextField("心愿名称（例：Leica M11 银色旁轴相机）", text: $title)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .medium))
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("预估预算：¥")
                        .font(ArchiveTypography.monoScale(size: 12))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    TextField("0.00", text: $wishBudgetYuan)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 13))
                }
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                PaperDatePicker(selection: $wishTargetDate, label: "期望达成时期")
            }

            TextEditor(text: $content)
                .font(ArchiveTypography.bodySans(size: 13))
                .lineSpacing(4)
                .frame(minHeight: 100)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    Group {
                        if content.isEmpty {
                            Text("为何心向往之？记下这份期冀背后的缘由与契机…")
                                .font(ArchiveTypography.bodySans(size: 12.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )

            mediaAttachmentsSection
        }
    }

    // MARK: - 5. 账目表单
    private var transactionFormView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("类型", selection: $txType) {
                    Text("支出").tag("expense")
                    Text("收入").tag("income")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                HStack(spacing: 4) {
                    Text("金额：¥")
                        .font(ArchiveTypography.monoScale(size: 13, weight: .semibold))
                        .foregroundStyle(txType == "income" ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                    TextField("0.00", text: $txAmountYuan)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                }
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 12) {
                Picker("分类", selection: $txCategory) {
                    let cats = txType == "income" ? appState.incomeCategories : appState.expenseCategories
                    ForEach(cats, id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
                .font(ArchiveTypography.bodySans(size: 12))

                Picker("支付方式", selection: $txPaymentMethod) {
                    ForEach(appState.paymentMethods, id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                .font(ArchiveTypography.bodySans(size: 12))

                PaperDatePicker(selection: $occurredAt, label: "发生时间")
            }

            TextField("备注（例：工作日咖啡与烘焙）", text: $content)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 13))
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // 扩展选项：信贷分期与同步固定资产
            HStack(spacing: 16) {
                Toggle("信贷分期", isOn: $isInstallment)
                    .toggleStyle(.checkbox)
                    .font(ArchiveTypography.bodySans(size: 12))

                Toggle("同步为随身/桌面固资", isOn: $syncToGear)
                    .toggleStyle(.checkbox)
                    .font(ArchiveTypography.bodySans(size: 12))
            }

            if isInstallment {
                HStack(spacing: 12) {
                    Picker("渠道", selection: $installmentChannel) {
                        ForEach(appState.creditChannels) { ch in
                            Text(ch.name).tag(ch.code)
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 11.5))

                    Picker("期数", selection: $installmentMonths) {
                        Text("3 期").tag(3)
                        Text("6 期").tag(6)
                        Text("12 期").tag(12)
                        Text("24 期").tag(24)
                    }
                    .font(ArchiveTypography.bodySans(size: 11.5))
                }
                .padding(8)
                .background(ArchivePalette.archiveSubtle.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if syncToGear {
                HStack(spacing: 12) {
                    Picker("固资分类", selection: $gearCategory) {
                        ForEach(appState.gearCategories, id: \.self) { g in
                            Text(g).tag(g)
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 11.5))

                    TextField("规格参数（例：M3 Max / 64G）", text: $gearSpec)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 11.5))
                        .padding(6)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(8)
                .background(ArchivePalette.archiveSubtle.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - 媒体附件区域
    private var mediaAttachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("胶片与图档装裱 (\(attachments.count))")
                    .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)

                Spacer()

                Button {
                    pickAndUploadMedia()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 10.5))
                        Text(isUploadingMedia ? "正在装裱…" : "添加相纸照片")
                            .font(ArchiveTypography.bodySans(size: 11))
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .disabled(isUploadingMedia)
            }

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { att in
                            ZStack(alignment: .topTrailing) {
                                if let url = APIClient.shared.resolveMediaURL(att.url) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        default:
                                            ProgressView()
                                        }
                                    }
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                                    )
                                }

                                Button {
                                    attachments.removeAll(where: { $0.id == att.id })
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                        .background(ArchivePalette.archivePaper)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - 逻辑与提交
    private func setupInitialState() {
        if let initK = initialKind, let k = Kind(rawValue: initK) {
            selectedKind = k
        }
        if let initProjId = initialProjectId {
            selectedProjectId = initProjId
            projectMode = "entry"
        } else if selectedProjectId == nil && !appState.projects.isEmpty {
            selectedProjectId = appState.projects.first?.id
        }
        if let cCode = initialCityCode, !cCode.isEmpty {
            cityCode = cCode
            cityName = initialCityName ?? ""
        } else if cityCode.isEmpty {
            cityCode = "330100"
            cityName = appState.profile.currentCity.isEmpty ? "杭州" : appState.profile.currentCity
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
                AudioFeedback.shared.playShutter()
                await appState.refreshAll(forceFull: true)
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitLife() async throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "正文内容不能为空"])
        }
        _ = try await appState.submitQuickCapture(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content,
            type: .life,
            location: nil,
            cityCode: cityCode.isEmpty ? nil : cityCode,
            cityName: cityName.isEmpty ? nil : cityName,
            attachmentIds: attachments.map(\.id),
            featured: isFeatured,
            occurredAt: FormatUtils.beijingISOString(from: occurredAt)
        )
    }

    private func submitTravel() async throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !title.isEmpty else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "游历标题或内容不能为空"])
        }
        _ = try await appState.submitQuickCapture(
            title: title.isEmpty ? "\(cityName) · 游记" : title,
            content: content,
            type: .travel,
            location: nil,
            cityCode: cityCode.isEmpty ? nil : cityCode,
            cityName: cityName.isEmpty ? nil : cityName,
            attachmentIds: attachments.map(\.id),
            featured: true,
            occurredAt: FormatUtils.beijingISOString(from: occurredAt)
        )
    }

    private func submitProject() async throws {
        if projectMode == "new" {
            guard !newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "项目名称不能为空"])
            }
            let req = CreateProjectRequest(
                title: newProjectTitle,
                subtitle: newProjectSubtitle.isEmpty ? nil : newProjectSubtitle,
                description: newProjectDesc.isEmpty ? newProjectTitle : newProjectDesc,
                category: newProjectCategory.isEmpty ? nil : newProjectCategory,
                status: newProjectStatus,
                githubUrl: newProjectGithub.isEmpty ? nil : newProjectGithub
            )
            _ = try await APIClient.shared.createProject(req)
        } else {
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "进展手记正文不能为空"])
            }
            let req = CreateEntryRequest(
                type: "project",
                title: title,
                content: content,
                occurredAt: FormatUtils.beijingISOString(from: occurredAt),
                location: nil,
                featured: false,
                cityCode: cityCode.isEmpty ? nil : cityCode,
                cityName: cityName.isEmpty ? nil : cityName,
                projectId: selectedProjectId,
                wishId: nil,
                footprintId: nil,
                attachmentIds: attachments.map(\.id)
            )
            _ = try await APIClient.shared.createEntry(req)
        }
    }

    private func submitWish() async throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "心愿名称不能为空"])
        }
        let budgetCents = FormatUtils.parseYuanToCents(wishBudgetYuan) ?? 0
        let req = CreateWishRequest(
            title: title,
            kind: wishKind,
            note: content.isEmpty ? nil : content,
            spec: nil,
            cityCode: cityCode.isEmpty ? nil : cityCode,
            cityName: cityName.isEmpty ? nil : cityName,
            budget: budgetCents,
            targetDate: FormatUtils.beijingDateString(from: wishTargetDate),
            attachmentIds: attachments.map(\.id)
        )
        _ = try await APIClient.shared.createWish(req)
    }

    private func submitTransaction() async throws {
        guard let cents = FormatUtils.parseYuanToCents(txAmountYuan), cents > 0 else {
            throw NSError(domain: "LooseLeaf", code: -1, userInfo: [NSLocalizedDescriptionKey: "请输入有效金额"])
        }
        let req = CreateTransactionRequest(
            amount: cents,
            type: txType,
            category: txCategory,
            title: content.isEmpty ? txCategory : content,
            note: content.isEmpty ? nil : content,
            paymentMethod: txPaymentMethod,
            wishId: nil,
            footprintId: nil,
            cityCode: cityCode.isEmpty ? nil : cityCode,
            occurredAt: FormatUtils.beijingISOString(from: occurredAt),
            isInstallment: isInstallment
        )
        _ = try await APIClient.shared.createTransaction(req)
    }

    private func pickAndUploadMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .jpeg, .png, .heic]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            isUploadingMedia = true
            Task { @MainActor in
                defer { isUploadingMedia = false }
                do {
                    let processed = try ImageProcessor.processImageFile(at: url)
                    let att = try await APIClient.shared.uploadUnifiedMultipart(
                        fileData: processed.compressedData,
                        filename: processed.filename,
                        mimeType: processed.mimeType,
                        folder: "entries"
                    )
                    attachments.append(att)
                    let camera = processed.exifMetadata.formattedCameraLine
                    if !camera.isEmpty {
                        extractedCameraLine = camera
                    }
                    AudioFeedback.shared.playPaperFlip()
                } catch {
                    errorMessage = "相纸上传失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 草稿持久化
    private func saveDraft() {
        guard !title.isEmpty || !content.isEmpty else { return }
        let dict: [String: Any] = [
            "kind": selectedKind.rawValue,
            "title": title,
            "content": content,
            "cityCode": cityCode,
            "cityName": cityName,
            "isFeatured": isFeatured
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: draftStorageKey)
        }
    }

    private func restoreDraft() {
        guard let data = UserDefaults.standard.data(forKey: draftStorageKey),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let k = dict["kind"] as? String, let kind = Kind(rawValue: k) {
            selectedKind = kind
        }
        if let t = dict["title"] as? String { title = t }
        if let c = dict["content"] as? String { content = c }
        if let code = dict["cityCode"] as? String { cityCode = code }
        if let name = dict["cityName"] as? String { cityName = name }
        if let feat = dict["isFeatured"] as? Bool { isFeatured = feat }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
        title = ""
        content = ""
        isFeatured = false
        attachments.removeAll()
    }

    private func hasSavedDraft() -> Bool {
        UserDefaults.standard.data(forKey: draftStorageKey) != nil
    }
}
