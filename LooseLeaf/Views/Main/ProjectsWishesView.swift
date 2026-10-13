import SwiftUI

/// 造物、心愿单与山川行迹视图 (ProjectsWishesView)
/// 遵循「记录为一切的母体 (Record-First Architecture)」与「典藏票根 (RC-98)」规范
public struct ProjectsWishesView: View {
    @Bindable var appState: AppState

    public enum SubTab: String, CaseIterable {
        case wishes = "三维心愿单"
        case footprints = "山川行迹票根"
        case projects = "造物与项目"
    }

    @State private var selectedTab: SubTab = .wishes
    @State private var showNewWishSheet: Bool = false
    @State private var showNewFootprintSheet: Bool = false

    // 新建心愿表单状态
    @State private var wishTitle: String = ""
    @State private var wishKind: String = "item"
    @State private var wishBudgetYuan: String = ""
    @State private var wishSpec: String = ""
    @State private var wishNote: String = ""

    // 新建足迹表单状态
    @State private var fpCityName: String = ""
    @State private var fpCityCode: String = "330100"
    @State private var fpTitle: String = ""
    @State private var fpNote: String = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("造物、心愿与山川行迹")
                            .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("二级投影均与主时间流伴生联动 · 无孤立数据孤岛")
                            .font(ArchiveTypography.bodySans(size: 12.5))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(SubTab.allCases, id: \.rawValue) { tab in
                            PaperPillButton(
                                title: tab.rawValue,
                                isSelected: selectedTab == tab
                            ) {
                                selectedTab = tab
                                AudioFeedback.shared.playPaperFlip()
                            }
                        }
                    }
                }

                switch selectedTab {
                case .wishes:
                    wishesSection
                case .footprints:
                    footprintsSection
                case .projects:
                    projectsSection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showNewWishSheet) {
            newWishSheetView
        }
        .sheet(isPresented: $showNewFootprintSheet) {
            newFootprintSheetView
        }
    }

    // MARK: - 1. 三维心愿单展厅

    private var wishesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("向往风物 · 共 \(appState.wishes.count) 项心愿")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                if appState.isPaired {
                    Button {
                        showNewWishSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("许下新心愿")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                }
            }

            if appState.wishes.isEmpty {
                emptyPlaceholder(title: "心愿草单尚且留白", subtitle: "记下一件心仪器物、一处远方山川或一项阶段目标")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(appState.wishes) { wish in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(wishKindLabel(wish.kind))
                                    .font(ArchiveTypography.monoScale(size: 10.5))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))

                                Spacer()

                                Text(wishStatusLabel(wish.status))
                                    .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                                    .foregroundStyle(wish.status == "fulfilled" ? ArchivePalette.accentMoss : ArchivePalette.inkMuted)
                            }

                            Text(wish.title)
                                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)

                            if let spec = wish.spec, !spec.isEmpty {
                                Text(spec)
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                            }

                            if let note = wish.note, !note.isEmpty {
                                Text(note)
                                    .font(ArchiveTypography.bodySans(size: 12))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                    .lineLimit(2)
                            }

                            Divider().overlay(ArchivePalette.borderSubtle)

                            HStack {
                                Text("意向预算 \(FormatUtils.formattedYuan(cents: wish.budget, includeSymbol: true))")
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Spacer()
                                if wish.actualCost > 0 {
                                    Text("实付 \(FormatUtils.formattedYuan(cents: wish.actualCost, includeSymbol: true))")
                                        .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                }
                            }
                        }
                        .padding(14)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                        )
                    }
                }
            }
        }
    }

    // MARK: - 2. 山川行迹特种纸票根架 (RC-98)

    private var footprintsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("山川行迹 · 典藏票根印信架 (\(appState.footprints.count) 程)")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                if appState.isPaired {
                    Button {
                        showNewFootprintSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill.viewfinder")
                            Text("点亮城市足迹")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                }
            }

            if appState.footprints.isEmpty {
                emptyPlaceholder(title: "行迹票根盒尚待启程", subtitle: "在时间流记录带城市的游记或在此直接点亮足迹，均会自动沉淀特种纸票根")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(appState.footprints) { fp in
                        HStack(spacing: 0) {
                            // 左联：目的地印章存根
                            VStack(alignment: .leading, spacing: 6) {
                                Text(fp.cityName)
                                    .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                Text(FormatUtils.parseOccurredDate(fp.visitedAt).dotDate)
                                    .font(ArchiveTypography.monoScale(size: 10.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Spacer(minLength: 4)
                                Text("散页 \(max(1, fp.entriesCount ?? 1)) 篇")
                                    .font(ArchiveTypography.monoScale(size: 10.5))
                                    .foregroundStyle(ArchivePalette.accentMoss)
                            }
                            .frame(width: 105, alignment: .leading)
                            .padding(12)

                            // 齿孔虚线分割
                            Rectangle()
                                .fill(ArchivePalette.borderDivider)
                                .frame(width: 0.5)
                                .padding(.vertical, 8)

                            // 右联：旅程手记正券
                            VStack(alignment: .leading, spacing: 6) {
                                Text((fp.title?.isEmpty == false) ? fp.title! : "\(fp.cityName) · 行旅手记")
                                    .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                    .lineLimit(1)

                                Text((fp.note?.isEmpty == false) ? fp.note! : "行至此处，留下一纸驻足印记。")
                                    .font(ArchiveTypography.bodySans(size: 12))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                    .lineLimit(2)

                                Spacer(minLength: 4)

                                if let spent = fp.totalSpent, spent > 0 {
                                    Text("旅途花销 \(FormatUtils.formattedYuan(cents: spent, includeSymbol: true))")
                                        .font(ArchiveTypography.monoScale(size: 10.5))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                        )
                    }
                }
            }
        }
    }

    // MARK: - 3. 造物与项目专柜

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("手艺与造物 · 共 \(appState.projects.count) 项")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            if appState.projects.isEmpty {
                emptyPlaceholder(title: "尚无造物归档", subtitle: "软件架构实验、开源工具与生活手艺方案将在此静默陈列")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(appState.projects) { proj in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                if let cat = proj.category, !cat.isEmpty {
                                    Text(cat)
                                        .font(ArchiveTypography.monoScale(size: 10.5))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                }
                                Spacer()
                                if let status = proj.status, !status.isEmpty {
                                    Text(status)
                                        .font(ArchiveTypography.monoScale(size: 10.5))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                }
                            }

                            Text(proj.title)
                                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)

                            if let sub = proj.subtitle, !sub.isEmpty {
                                Text(sub)
                                    .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                            }

                            Text(proj.description)
                                .font(ArchiveTypography.bodySans(size: 12))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                                .lineLimit(3)

                            if let gh = proj.githubUrl, !gh.isEmpty, let url = URL(string: gh) {
                                Link(destination: url) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.right.square")
                                        Text("访问源码仓库")
                                    }
                                    .font(ArchiveTypography.monoScale(size: 11))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                                }
                            }
                        }
                        .padding(14)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                        )
                    }
                }
            }
        }
    }

    // MARK: - 弹窗表单

    private var newWishSheetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("许下新心愿")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 6) {
                PaperPillButton(title: "心仪好物", isSelected: wishKind == "item") { wishKind = "item" }
                PaperPillButton(title: "远方旅程", isSelected: wishKind == "travel") { wishKind = "travel" }
                PaperPillButton(title: "阶段里程碑", isSelected: wishKind == "milestone") { wishKind = "milestone" }
            }

            TextField("心愿名称", text: $wishTitle)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("规格或补充（可选）", text: $wishSpec)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("预期预算金额（元，如 2399.00）", text: $wishBudgetYuan)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 13))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("心愿初衷手记", text: $wishNote)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Button("取消") { showNewWishSheet = false }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("存入心愿单") {
                    let cents = FormatUtils.parseYuanToCents(wishBudgetYuan) ?? 0
                    Task {
                        let req = CreateWishRequest(
                            title: wishTitle,
                            kind: wishKind,
                            note: wishNote,
                            spec: wishSpec,
                            budget: cents
                        )
                        _ = try? await APIClient.shared.createWish(req)
                        AudioFeedback.shared.playShutter()
                        await appState.loadProjectsWishesFootprints()
                        await appState.loadEntries(forceFull: true)
                        wishTitle = ""
                        wishSpec = ""
                        wishBudgetYuan = ""
                        wishNote = ""
                        showNewWishSheet = false
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(wishTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(ArchivePalette.archivePaper)
    }

    private var newFootprintSheetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("点亮城市行迹票根")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("城市中文名称（如：大理市、苏州市）", text: $fpCityName)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("6 位行政区划代码（如：532900）", text: $fpCityCode)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 12.5))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("旅程标题（如：春日苍山洱海漫游）", text: $fpTitle)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("行迹随笔手记", text: $fpNote)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Button("取消") { showNewFootprintSheet = false }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("镌刻票根并伴生入流") {
                    Task {
                        let req = CreateFootprintRequest(
                            cityCode: fpCityCode.trimmingCharacters(in: .whitespacesAndNewlines),
                            cityName: fpCityName.trimmingCharacters(in: .whitespacesAndNewlines),
                            title: fpTitle,
                            note: fpNote
                        )
                        _ = try? await APIClient.shared.createFootprint(req)
                        AudioFeedback.shared.playShutter()
                        await appState.loadProjectsWishesFootprints()
                        await appState.loadEntries(forceFull: true)
                        fpCityName = ""
                        fpTitle = ""
                        fpNote = ""
                        showNewFootprintSheet = false
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(fpCityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(ArchivePalette.archivePaper)
    }

    private func emptyPlaceholder(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(ArchiveTypography.editorialSerif(size: 14.5, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)
            Text(subtitle)
                .font(ArchiveTypography.bodySans(size: 12))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func wishKindLabel(_ kind: String) -> String {
        switch kind {
        case "travel": return "远方旅程"
        case "milestone": return "阶段里程碑"
        default: return "心仪好物"
        }
    }

    private func wishStatusLabel(_ status: String) -> String {
        switch status {
        case "fulfilled": return "已圆满归册"
        case "relinquished": return "已理性拔草"
        case "shelved": return "暂且搁置"
        default: return "静候圆梦"
        }
    }
}

/// 主理人生活手记与器物图鉴视图 (CuratorDossierView)
/// 严格遵守：100% 由 GET /api/v1/profile 动态驱动，严禁硬编码姓名或城市
public struct CuratorDossierView: View {
    @Bindable var appState: AppState

    @State private var showEditProfileSheet: Bool = false
    @State private var editName: String = ""
    @State private var editTitle: String = ""
    @State private var editCity: String = ""
    @State private var editLocation: String = ""
    @State private var editMotto: String = ""
    @State private var editBio: String = ""
    @State private var editManifesto: String = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        let prof = appState.profile
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. 主理人名片与暗房肖像
                HStack(alignment: .top, spacing: 20) {
                    if !prof.avatarUrl.isEmpty, let url = APIClient.shared.resolveMediaURL(prof.avatarUrl) {
                        FilmFrameView(
                            imageURL: url,
                            caption: prof.name.isEmpty ? "主理人肖像" : prof.name,
                            metaText: prof.displayCity,
                            maxHeight: 130
                        )
                        .frame(width: 150)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(prof.name.isEmpty ? "主理人档案待填写" : prof.name)
                                .font(ArchiveTypography.editorialSerif(size: 22, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)

                            if !prof.title.isEmpty {
                                Text(prof.title)
                                    .font(ArchiveTypography.bodySans(size: 12))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(ArchivePalette.archiveSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }

                            Spacer()

                            if appState.isPaired {
                                Button("修订档案") {
                                    editName = prof.name
                                    editTitle = prof.title
                                    editCity = prof.currentCity
                                    editLocation = prof.location
                                    editMotto = prof.motto
                                    editBio = prof.bio
                                    editManifesto = prof.manifesto
                                    showEditProfileSheet = true
                                }
                                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            }
                        }

                        if !prof.displayCity.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "location")
                                    .font(.system(size: 11))
                                Text("常居与当下坐标：\(prof.location.isEmpty ? prof.currentCity : prof.location)")
                                    .font(ArchiveTypography.monoScale(size: 11.5))
                            }
                            .foregroundStyle(ArchivePalette.inkMuted)
                        }

                        if !prof.motto.isEmpty {
                            Text("“\(prof.motto)”")
                                .font(ArchiveTypography.editorialSerif(size: 15))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(.top, 2)
                        }

                        if !prof.bio.isEmpty {
                            Text(prof.bio)
                                .font(ArchiveTypography.bodySans(size: 13))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                        }

                        if !prof.manifesto.isEmpty {
                            Text(prof.manifesto)
                                .font(ArchiveTypography.bodySans(size: 12.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(18)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )

                // 2. 随身器物图鉴 (EDC Gear)
                VStack(alignment: .leading, spacing: 12) {
                    Text("随身器物与桌面装备图鉴 (\(prof.edcGear.count))")
                        .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    if prof.edcGear.isEmpty {
                        Text("尚无随身器物记录。在资产中枢或 Web 管理台中添置设备后将自动同步展示。")
                            .font(ArchiveTypography.bodySans(size: 12.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(prof.edcGear) { gear in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(gear.category)
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(ArchivePalette.accentWarm)
                                        Spacer()
                                        Text(gear.status == "sold" ? "已转让回血" : "服役中")
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(gear.status == "sold" ? ArchivePalette.inkMuted : ArchivePalette.accentMoss)
                                    }

                                    Text(gear.name)
                                        .font(ArchiveTypography.editorialSerif(size: 14.5, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.inkPrimary)

                                    if let spec = gear.spec, !spec.isEmpty {
                                        Text(spec)
                                            .font(ArchiveTypography.monoScale(size: 11))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                    }

                                    if let price = gear.priceCents, price > 0 {
                                        Text("购入记录 \(FormatUtils.formattedYuan(cents: price, includeSymbol: true))")
                                            .font(ArchiveTypography.monoScale(size: 11))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                    }
                                }
                                .padding(14)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showEditProfileSheet) {
            editProfileSheetView
        }
    }

    private var editProfileSheetView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("修订主理人档案")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("主理人称谓", text: $editName)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("身份标签", text: $editTitle)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 8) {
                TextField("当前城市（如：杭州）", text: $editCity)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                TextField("完整常居地（如：中国 · 杭州）", text: $editLocation)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            TextField("精神信条 Motto", text: $editMotto)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("个人签名 Bio", text: $editBio)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Button("取消") { showEditProfileSheet = false }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存档案") {
                    Task {
                        let req = UpdateProfileRequest(
                            name: editName,
                            title: editTitle,
                            bio: editBio,
                            location: editLocation,
                            currentCity: editCity,
                            motto: editMotto,
                            manifesto: editManifesto
                        )
                        _ = try? await APIClient.shared.updateCuratorProfile(req)
                        AudioFeedback.shared.playShutter()
                        await appState.loadConfigAndProfile()
                        showEditProfileSheet = false
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 420)
        .background(ArchivePalette.archivePaper)
    }
}
