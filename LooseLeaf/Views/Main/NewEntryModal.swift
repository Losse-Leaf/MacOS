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
    @State private var didSubmitSuccessfully: Bool = false
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
    /// 拖拽悬停高亮
    @State private var isMediaDropTargeted: Bool = false

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
    @State private var wishSpec: String = ""
    @State private var wishCityCode: String = ""
    @State private var wishCityName: String = ""
    @State private var wishTargetDate: Date = Date()

    // 账目专有
    @State private var txType: String = "expense" // expense, income
    @State private var txAmountYuan: String = ""
    @State private var txCategory: String = "餐饮"
    @State private var txPaymentMethod: String = "微信支付"
    @State private var selectedWishId: Int?
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

                    // 表单主体切换
                    Group {
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
            if let err = errorMessage {
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
            .disabled(isSubmitting)
            .keyboardShortcut(.return, modifiers: [.command])
        }
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

            TextField("记下这一刻的思绪、见闻或生活琐记…", text: $content, axis: .vertical)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 13))
                .lineLimit(5...10)
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 12) {
                PaperDatePicker(selection: $occurredAt, enableTime: true, label: "发生时刻")
                PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName)
                Toggle("精选散页", isOn: $isFeatured)
                    .toggleStyle(.paperCheckbox)
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
                    let fpOptions: [PaperSelectOption<Int?>] = [PaperSelectOption(value: nil, label: "新建独立漫游")] + appState.footprints.map { fp in
                        PaperSelectOption(value: fp.id, label: "\(fp.cityName) · \(fp.title ?? "行旅")")
                    }
                    PaperSelect(selection: $selectedFootprintId, options: fpOptions, label: "关联足迹")
                }
            }

            HStack(spacing: 12) {
                PaperDatePicker(selection: $occurredAt, enableTime: true, label: "启程/抵达时刻")
                PaperDatePicker(selection: $departedAt, enableTime: true, label: "离开时刻")
            }

            TextField("旅途标题（例：西湖暮色寻茶记）", text: $title)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .medium))
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextField("记下旅途行迹、见闻感受与山川光影…", text: $content, axis: .vertical)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 13))
                .lineLimit(5...10)
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            mediaAttachmentsSection
        }
    }

    // MARK: - 3. 造物表单
    private var projectFormView: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSegmentedControl(
                selection: $projectMode,
                items: [
                    PaperSegmentItem("entry", title: "追加进展手记", icon: "pencil.line"),
                    PaperSegmentItem("new", title: "立项新造物", icon: "plus.circle")
                ]
            )

            if projectMode == "new" {
                TextField("造物项目名称（例：Loose-Leaf macOS 客户端）", text: $newProjectTitle)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .medium))
                    .padding(10)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 12) {
                    let catOptions = appState.projectCategories.map { PaperSelectOption(value: $0, label: $0) }
                    PaperSelect(selection: $newProjectCategory, options: catOptions, label: "项目类别")

                    let statusOptions = [
                        PaperSelectOption(value: "Active", label: "进行中 (Active)"),
                        PaperSelectOption(value: "Archived", label: "已完结 (Archived)")
                    ]
                    PaperSelect(selection: $newProjectStatus, options: statusOptions, label: "当前状态")
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

                TextField("项目简介与核心设计思想…", text: $newProjectDesc, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .lineLimit(3...6)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                if appState.projects.isEmpty {
                    Text("当前尚无进行中的造物项目，请切换至「立项新造物」完成初始立项。")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                } else {
                    let projOptions: [PaperSelectOption<Int?>] = appState.projects.map { proj in
                        PaperSelectOption(value: proj.id as Int?, label: proj.title, sublabel: proj.category ?? "未分类")
                    }
                    PaperSelect(selection: $selectedProjectId, options: projOptions, placeholder: "选择归属造物项目…", label: "归属造物")

                    TextField("手记主题（例：完成 1:1 架构对齐）", text: $title)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.editorialSerif(size: 14.5, weight: .medium))
                        .padding(10)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    TextField("记录造物阶段性进展与攻坚思考…", text: $content, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.bodySans(size: 13))
                        .lineLimit(5...10)
                        .padding(10)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 12) {
                        PaperDatePicker(selection: $occurredAt, enableTime: true, label: "进展时刻")
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
            PaperSegmentedControl(
                selection: $wishKind,
                items: [
                    PaperSegmentItem("item", title: "好物器物", icon: "bag"),
                    PaperSegmentItem("travel", title: "行旅探索", icon: "airplane"),
                    PaperSegmentItem("milestone", title: "阶段里程碑", icon: "flag.checkered")
                ]
            )

            TextField(
                wishKind == "travel" ? "旅程目的地或漫游愿景（例：京都秋日赏枫 / 环勃朗峰徒步）" :
                (wishKind == "milestone" ? "里程碑名称（例：跑完人生第一场半马 / 独立发布首个产品）" : "心愿好物名称（例：Leica M11 银色旁轴相机）"),
                text: $title
            )
            .textFieldStyle(.plain)
            .font(ArchiveTypography.editorialSerif(size: 15, weight: .medium))
            .padding(10)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if wishKind == "item" {
                TextField("规格型号或意向（例：黑色银顶 / 35mm F1.4 / 国行现货）", text: $wishSpec)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if wishKind == "travel" {
                PaperCityPicker(selectedCode: $wishCityCode, selectedName: $wishCityName, placeholder: "点选目的地省市…")
            }

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

            TextField("为何心向往之？记下这份期冀背后的缘由、契机与初心…", text: $content, axis: .vertical)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 13))
                .lineLimit(4...7)
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            mediaAttachmentsSection
        }
    }

    // MARK: - 5. 账目表单
    private var transactionFormView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PaperSegmentedControl(
                    selection: $txType,
                    items: [
                        PaperSegmentItem("expense", title: "支出", icon: "arrow.down.forward"),
                        PaperSegmentItem("income", title: "收入", icon: "arrow.up.forward")
                    ]
                )
                .frame(width: 160)

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
                let cats = txType == "income" ? appState.incomeCategories : appState.expenseCategories
                let catOptions = cats.map { PaperSelectOption(value: $0, label: $0) }
                PaperSelect(selection: $txCategory, options: catOptions, label: "分类")

                let payOptions = appState.paymentMethods.map { PaperSelectOption(value: $0, label: $0) }
                PaperSelect(selection: $txPaymentMethod, options: payOptions, label: "支付方式")

                PaperDatePicker(selection: $occurredAt, enableTime: true, label: "发生时间")
            }

            // 关联心愿或足迹票根 (选填)
            HStack(spacing: 12) {
                if !appState.wishes.isEmpty {
                    let wishOptions: [PaperSelectOption<Int?>] = [PaperSelectOption(value: nil, label: "不关联心愿")] + appState.wishes.map { w in
                        PaperSelectOption(value: w.id as Int?, label: w.title, badge: w.status == "fulfilled" ? "已圆满" : nil)
                    }
                    PaperSelect(selection: $selectedWishId, options: wishOptions, label: "圆满心愿")
                }

                if !appState.footprints.isEmpty {
                    let fpOptions: [PaperSelectOption<Int?>] = [PaperSelectOption(value: nil, label: "不关联足迹")] + appState.footprints.map { f in
                        PaperSelectOption(value: f.id as Int?, label: "\(f.cityName) · \(f.title ?? "行旅")")
                    }
                    PaperSelect(selection: $selectedFootprintId, options: fpOptions, label: "旅途花销")
                }
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
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: 12))

                Toggle("同步为随身/桌面固资", isOn: $syncToGear)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: 12))
            }

            if isInstallment {
                HStack(spacing: 12) {
                    let channelOptions = appState.creditChannels.map { PaperSelectOption(value: $0.code, label: $0.name) }
                    PaperSelect(selection: $installmentChannel, options: channelOptions, label: "渠道")

                    let monthOptions = [3, 6, 12, 24].map { PaperSelectOption(value: $0, label: "\($0) 期") }
                    PaperSelect(selection: $installmentMonths, options: monthOptions, label: "期数")
                }
                .padding(8)
                .background(ArchivePalette.archiveSubtle.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if syncToGear {
                HStack(spacing: 12) {
                    let gearCatOptions = appState.gearCategories.map { PaperSelectOption(value: $0, label: $0) }
                    PaperSelect(selection: $gearCategory, options: gearCatOptions, label: "固资分类")

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
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)

                Spacer()

                Button {
                    pickAndUploadMedia()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 10.5))
                        Text(isUploadingMedia ? "正在装裱…" : "添加相纸照片")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .disabled(isUploadingMedia)
                .help("从「照片」App 或访达拖拽照片到此处亦可装裱")
            }

            // 拖拽装裱：与暗房保持一致的拖入体验
            .onDrop(of: [.image, .fileURL, .rawImage], isTargeted: $isMediaDropTargeted) { providers in
                handleDrop(providers: providers)
            }
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                    .stroke(isMediaDropTargeted ? ArchivePalette.accentWarm : .clear, lineWidth: 1.5)
                    .padding(.vertical, 4)
                    .allowsHitTesting(false)
            )

            // 上传进度（原先 uploadProgress 是死状态，从不展示）
            if isUploadingMedia {
                HStack(spacing: 8) {
                    ProgressView(value: uploadProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 180)
                    Text("正在装裱 \(Int(uploadProgress * 100))%")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .accessibilityLabel("正在装裱相片")
            }

            // 相机底款信息（原先只写不读，用户看不到 EXIF 相机信息）
            if !extractedCameraLine.isEmpty {
                Text(extractedCameraLine)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .accessibilityLabel("相机信息：\(extractedCameraLine)")
            }

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { att in
                            ZStack(alignment: .topTrailing) {
                                if let url = APIClient.shared.resolveMediaURL(att.url) {
                                    CachedFilmImageView(url: url, maxHeight: 72)
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
                didSubmitSuccessfully = true
                if appState.enablesHapticFeedback {
                    ArchiveFeedback.success()
                }
                // 不再全量重拉：提交结果已经通过 SyncManager 乐观写入本地快照，
                // 全量 refreshAll 会带来数秒等待与整页重绘。
                await appState.loadConfigAndProfile()
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
        let finalSpec = wishKind == "item" ? (wishSpec.isEmpty ? nil : wishSpec) : nil
        let finalCityCode = wishKind == "travel" ? (wishCityCode.isEmpty ? nil : wishCityCode) : nil
        let finalCityName = wishKind == "travel" ? (wishCityName.isEmpty ? nil : wishCityName) : nil

        let req = CreateWishRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: wishKind,
            note: content.isEmpty ? nil : content,
            spec: finalSpec,
            cityCode: finalCityCode,
            cityName: finalCityName,
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
        let isExp = txType == "expense"
        let installmentPay: Int64? = (isExp && isInstallment && installmentMonths > 0) ? (cents / Int64(installmentMonths)) : nil

        let req = CreateTransactionRequest(
            amount: cents,
            type: txType,
            category: txCategory,
            title: content.isEmpty ? txCategory : content,
            note: content.isEmpty ? nil : content,
            paymentMethod: txPaymentMethod,
            wishId: selectedWishId,
            footprintId: selectedFootprintId,
            cityCode: cityCode.isEmpty ? nil : cityCode,
            occurredAt: FormatUtils.beijingISOString(from: occurredAt),
            isInstallment: isExp && isInstallment,
            installmentChannelCode: (isExp && isInstallment) ? installmentChannel : nil,
            installmentTotalAmount: (isExp && isInstallment) ? cents : nil,
            installmentMonths: (isExp && isInstallment) ? installmentMonths : nil,
            installmentMonthlyPay: installmentPay,
            installmentRemainMonths: (isExp && isInstallment) ? installmentMonths : nil,
            repaymentDay: (isExp && isInstallment) ? customRepaymentDay : nil,
            linkGearAsset: isExp && syncToGear,
            gearCategory: (isExp && syncToGear) ? gearCategory : nil,
            gearSpec: (isExp && syncToGear) ? (gearSpec.isEmpty ? nil : gearSpec) : nil
        )
        _ = try await APIClient.shared.createTransaction(req)
    }

    private func pickAndUploadMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .jpeg, .png, .heic, .rawImage]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            uploadMediaFiles(panel.urls)
        }
    }

    /// 批量装裱相片：逐张后台压制 + 上传，单张失败不影响其余
    private func uploadMediaFiles(_ urls: [URL]) {
        isUploadingMedia = true
        uploadProgress = 0
        Task { @MainActor in
            defer {
                isUploadingMedia = false
                uploadProgress = 0
            }
            var failures: [String] = []
            for (index, url) in urls.enumerated() {
                do {
                    // 关键：4K 解码 + JPEG 重编码必须离开主线程，否则选图后 UI 冻结数秒
                    let processed = try await ImageProcessor.processImageFileInBackground(at: url)
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
                } catch {
                    failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                }
                uploadProgress = Double(index + 1) / Double(max(urls.count, 1))
            }
            if !failures.isEmpty {
                errorMessage = failures.count == 1
                    ? "相纸上传失败：\(failures[0])"
                    : "\(failures.count) 张相纸上传失败：\(failures.prefix(3).joined(separator: "；"))"
            }
        }
    }

    /// 拖拽装裱：支持多文件同时拖入
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        // NSItemProvider 不是 Sendable：用 @unchecked Sendable 盒子安全跨隔离域传递
        let box = DropLoader.makeProviderBox(providers)
        Task { @MainActor in
            let urls = await DropLoader.loadDroppablePhotoURLs(from: box)
            guard !urls.isEmpty else { return }
            uploadMediaFiles(urls)
        }
        return true
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
        // 关键：调用方显式指定的形态 / 项目 / 城市优先于草稿。
        // 原先草稿无条件覆盖 selectedKind，导致用户从「造物」入口打开却落到「日常」。
        if initialKind == nil,
           let k = dict["kind"] as? String,
           let kind = Kind(rawValue: k) {
            selectedKind = kind
        }
        if initialProjectId == nil, let pid = dict["projectId"] as? Int {
            selectedProjectId = pid
        }
        if let t = dict["title"] as? String { title = t }
        if let c = dict["content"] as? String { content = c }
        if initialCityCode == nil || initialCityCode?.isEmpty == true {
            if let code = dict["cityCode"] as? String { cityCode = code }
            if let name = dict["cityName"] as? String { cityName = name }
        }
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
