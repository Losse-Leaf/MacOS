import SwiftUI

/// 造物、心愿单与山川行迹视图 (ProjectsWishesView)
/// 遵循「记录为一切的母体 (Record-First Architecture)」与「典藏票根 (RC-98)」规范
/// 主理人全权管理：心愿圆满归册与编辑、山川足迹自动解析城市代码与编辑、造物项目全权 CRUD
@MainActor
public struct ProjectsWishesView: View {
    @Bindable var appState: AppState

    public enum SubTab: String, CaseIterable {
        case wishes = "三维心愿单"
        case footprints = "山川行迹票根"
        case projects = "造物与项目"
    }

    @State private var selectedTab: SubTab = .wishes

    // 心愿单状态
    @State private var showNewWishSheet: Bool = false
    @State private var resolvingWish: Wish?
    @State private var editingWish: Wish?
    @State private var wishToDelete: Wish?
    @State private var showDeleteWishConfirm: Bool = false

    // 足迹票根与星野状态
    @State private var showNewFootprintSheet: Bool = false
    @State private var editingFootprint: Footprint?
    @State private var footprintToDelete: Footprint?
    @State private var showDeleteFootprintConfirm: Bool = false
    @State private var footprintViewMode: Int = 0 // 0: 典藏票根, 1: 经纬星野
    @State private var selectedDrawerCity: DrawerCitySelection?
    @State private var showAlmanacSheet: Bool = false

    public struct DrawerCitySelection: Identifiable, Equatable {
        public var id: String { code }
        public let code: String
        public let name: String
    }

    // 造物项目状态
    @State private var showNewProjectSheet: Bool = false
    @State private var editingProject: Project?
    @State private var projectToDelete: Project?
    @State private var showDeleteProjectConfirm: Bool = false

    @State private var errorNotice: String?

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
                        Text("心愿、行迹与造物，皆在时光深处留痕")
                            .font(ArchiveTypography.bodySans(size: 12.5))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Button {
                            showAlmanacSheet = true
                            AudioFeedback.shared.playPaperFlip()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 11))
                                Text("年度年鉴")
                                    .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .background(ArchivePalette.accentWarm.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.accentWarm.opacity(0.35), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)

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

                if let errorNotice {
                    Text(errorNotice)
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.accentWarm)
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
            NewWishSheet(appState: appState) {
                showNewWishSheet = false
            }
        }
        .sheet(item: $resolvingWish) { wish in
            ResolveWishSheet(appState: appState, wish: wish) {
                resolvingWish = nil
            }
        }
        .sheet(item: $editingWish) { wish in
            EditWishSheet(appState: appState, wish: wish) {
                editingWish = nil
            }
        }
        .sheet(isPresented: $showNewFootprintSheet) {
            NewFootprintSheet(appState: appState) {
                showNewFootprintSheet = false
            }
        }
        .sheet(item: $editingFootprint) { fp in
            EditFootprintSheet(appState: appState, footprint: fp) {
                editingFootprint = nil
            }
        }
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet(appState: appState) {
                showNewProjectSheet = false
            }
        }
        .sheet(item: $editingProject) { proj in
            EditProjectSheet(appState: appState, project: proj) {
                editingProject = nil
            }
        }
        .sheet(item: $selectedDrawerCity) { sel in
            CityMemoryDrawerSheet(cityCode: sel.code, cityName: sel.name) {
                selectedDrawerCity = nil
            }
        }
        .sheet(isPresented: $showAlmanacSheet) {
            AnnualAlmanacSheet {
                showAlmanacSheet = false
            }
        }
        .confirmationDialog(
            "确认删除该项心愿印记？",
            isPresented: $showDeleteWishConfirm,
            titleVisibility: .visible
        ) {
            Button("删除心愿", role: .destructive) {
                if let target = wishToDelete {
                    deleteWish(target)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将从向往风物清单中移除。")
        }
        .confirmationDialog(
            "确认删除该座城市足迹票根？",
            isPresented: $showDeleteFootprintConfirm,
            titleVisibility: .visible
        ) {
            Button("删除票根", role: .destructive) {
                if let target = footprintToDelete {
                    deleteFootprint(target)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将从行迹印信盒中移除。")
        }
        .confirmationDialog(
            "确认删除该项手艺造物项目？",
            isPresented: $showDeleteProjectConfirm,
            titleVisibility: .visible
        ) {
            Button("删除项目", role: .destructive) {
                if let target = projectToDelete {
                    deleteProject(target)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将从造物货架中移除。")
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

            if appState.wishes.isEmpty {
                emptyPlaceholder(title: "心愿草单尚且留白", subtitle: "记下一件心仪器物、一处远方山川或一项阶段目标")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(appState.wishes) { wish in
                        WishCardView(
                            wish: wish,
                            onResolve: {
                                resolvingWish = wish
                            },
                            onEdit: {
                                editingWish = wish
                            },
                            onDelete: {
                                wishToDelete = wish
                                showDeleteWishConfirm = true
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - 2. 山川行迹特种纸票根架与经纬星野 (RC-98)

    private var footprintsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("山川行迹 · 经纬星野与典藏票根 (\(appState.footprints.count) 程)")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                HStack(spacing: 6) {
                    PaperPillButton(title: "典藏票根", isSelected: footprintViewMode == 0) {
                        footprintViewMode = 0
                        AudioFeedback.shared.playPaperFlip()
                    }
                    PaperPillButton(title: "经纬星野", isSelected: footprintViewMode == 1) {
                        footprintViewMode = 1
                        AudioFeedback.shared.playPaperFlip()
                    }
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
            } else if footprintViewMode == 1 {
                CelestialAtlasCanvasView(footprints: appState.footprints) { code, name in
                    AudioFeedback.shared.playPaperFlip()
                    selectedDrawerCity = DrawerCitySelection(code: code, name: name)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
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
                                HStack {
                                    Text((fp.title?.isEmpty == false) ? fp.title! : "\(fp.cityName) · 行旅手记")
                                        .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        editingFootprint = fp
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        footprintToDelete = fp
                                        showDeleteFootprintConfirm = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text((fp.note?.isEmpty == false) ? fp.note! : "行至此处，留下一纸驻足印记。")
                                    .font(ArchiveTypography.bodySans(size: 12))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                    .lineLimit(2)

                                Spacer(minLength: 4)

                                HStack {
                                    if let spent = fp.totalSpent, spent > 0 {
                                        Text("旅途花销 \(FormatUtils.formattedYuan(cents: spent, includeSymbol: true))")
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(ArchivePalette.accentWarm)
                                    }
                                    Spacer()
                                    Text("点击翻阅城市抽屉 →")
                                        .font(ArchiveTypography.monoScale(size: 10))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 115)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            AudioFeedback.shared.playPaperFlip()
                            selectedDrawerCity = DrawerCitySelection(code: fp.cityCode, name: fp.cityName)
                        }
                        .paperHover()
                    }
                }
            }
        }
    }

    // MARK: - 3. 造物与项目专柜

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("手艺与造物 · 共 \(appState.projects.count) 项")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                Button {
                    showNewProjectSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hammer")
                        Text("新建造物项目")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }

            if appState.projects.isEmpty {
                emptyPlaceholder(title: "尚无造物归档", subtitle: "软件架构实验、开源工具与生活手艺方案将在此静默陈列")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(appState.projects) { proj in
                        ProjectCardView(
                            proj: proj,
                            onEdit: {
                                editingProject = proj
                            },
                            onDelete: {
                                projectToDelete = proj
                                showDeleteProjectConfirm = true
                            }
                        )
                    }
                }
            }
        }
    }

    private func deleteWish(_ wish: Wish) {
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteWish(id: wish.id)
                AudioFeedback.shared.playTink()
                await appState.loadProjectsWishesFootprints()
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }

    private func deleteFootprint(_ fp: Footprint) {
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteFootprint(id: fp.id)
                AudioFeedback.shared.playTink()
                await appState.loadProjectsWishesFootprints()
            } catch {
                errorNotice = error.localizedDescription
            }
        }
    }

    private func deleteProject(_ proj: Project) {
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteProject(id: proj.id)
                AudioFeedback.shared.playTink()
                await appState.loadProjectsWishesFootprints()
            } catch {
                errorNotice = error.localizedDescription
            }
        }
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

/// 统一样式与等高对齐的心愿典藏卡片 (WishCardView)
struct WishCardView: View {
    let wish: Wish
    let onResolve: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 顶栏：分类标签徽章 + 状态微胶囊
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Image(systemName: kindIcon)
                        .font(.system(size: 9.5))
                    Text(kindTitle)
                        .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                }
                .foregroundStyle(kindColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(kindColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 5.5, height: 5.5)
                    Text(statusTitle)
                        .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                        .foregroundStyle(statusTextColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(statusBgColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.bottom, 10)

            // 2. 标题
            Text(wish.title)
                .font(ArchiveTypography.editorialSerif(size: 16.5, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)

            // 3. 规格
            if let spec = wish.spec, !spec.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.2")
                        .font(.system(size: 9))
                    Text(spec)
                        .font(ArchiveTypography.monoScale(size: 11, weight: .medium))
                }
                .foregroundStyle(ArchivePalette.inkSecondary)
                .padding(.top, 3)
                .lineLimit(1)
            }

            // 4. 手记备注
            if let note = wish.note, !note.isEmpty {
                Text(LocalizedStringKey(note))
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkSecondary.opacity(0.88))
                    .lineLimit(2)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }

            // 弹性占位：将底部预算与操作栏统一牢牢推向卡片底端，确保各卡片严格等高对齐
            Spacer(minLength: 12)

            // 5. 分割线
            Rectangle()
                .fill(ArchivePalette.borderDivider)
                .frame(height: 0.5)
                .padding(.vertical, 9)

            // 6. 底部：预算 / 实付金额 + 操作按钮栏
            HStack(alignment: .center) {
                if wish.status == "fulfilled" && wish.actualCost > 0 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("圆满实付")
                            .font(ArchiveTypography.bodySans(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        Text(FormatUtils.formattedYuan(cents: wish.actualCost, includeSymbol: true))
                            .font(ArchiveTypography.monoScale(size: 13, weight: .bold))
                            .foregroundStyle(ArchivePalette.accentMoss)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("意向预算")
                            .font(ArchiveTypography.bodySans(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        Text(FormatUtils.formattedYuan(cents: wish.budget, includeSymbol: true))
                            .font(ArchiveTypography.monoScale(size: 12.5, weight: .semibold))
                            .foregroundStyle(wish.budget > 0 ? ArchivePalette.inkPrimary : ArchivePalette.inkMuted)
                    }
                }

                Spacer()

                // 主理人操作区
                HStack(spacing: 6) {
                    if wish.status != "fulfilled" {
                        Button(action: onResolve) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("圆满心愿")
                                    .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(ArchivePalette.accentMoss)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(ArchivePalette.accentMoss.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.accentMoss.opacity(0.3), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                            Text("已归册")
                                .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                        }
                        .foregroundStyle(ArchivePalette.accentMoss)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(ArchivePalette.accentMoss.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("修订心愿")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("删除心愿")
                }
            }
        }
        .padding(14)
        .frame(minHeight: 195)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.6)
        )
        .shadow(color: ArchivePalette.inkPrimary.opacity(0.04), radius: 6, x: 0, y: 2)
        .paperHover()
    }

    private var kindIcon: String {
        switch wish.kind {
        case "travel": return "airplane"
        case "milestone": return "flag.fill"
        default: return "bag.fill"
        }
    }

    private var kindTitle: String {
        switch wish.kind {
        case "travel": return "远方旅程"
        case "milestone": return "阶段里程碑"
        default: return "心仪好物"
        }
    }

    private var kindColor: Color {
        switch wish.kind {
        case "travel": return ArchivePalette.categoryColor(for: "交通")
        case "milestone": return ArchivePalette.accentMoss
        default: return ArchivePalette.accentWarm
        }
    }

    private var statusTitle: String {
        switch wish.status {
        case "fulfilled": return "已圆满归册"
        case "relinquished": return "已理性拔草"
        case "shelved": return "暂且搁置"
        default: return "静候圆梦"
        }
    }

    private var statusDotColor: Color {
        switch wish.status {
        case "fulfilled": return ArchivePalette.accentMoss
        case "relinquished": return ArchivePalette.inkMuted
        case "shelved": return Color.orange.opacity(0.8)
        default: return ArchivePalette.accentWarm
        }
    }

    private var statusTextColor: Color {
        switch wish.status {
        case "fulfilled": return ArchivePalette.accentMoss
        case "relinquished": return ArchivePalette.inkMuted
        default: return ArchivePalette.inkSecondary
        }
    }

    private var statusBgColor: Color {
        switch wish.status {
        case "fulfilled": return ArchivePalette.accentMoss.opacity(0.10)
        case "relinquished": return ArchivePalette.borderSubtle
        default: return ArchivePalette.archivePaper
        }
    }
}

/// 统一样式与等高对齐的造物项目卡片 (ProjectCardView)
struct ProjectCardView: View {
    let proj: Project
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶栏：分类标签 + 状态标签
            HStack {
                if let cat = proj.category, !cat.isEmpty {
                    Text(cat)
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ArchivePalette.accentWarm.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                if let status = proj.status, !status.isEmpty {
                    Text(status)
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.accentMoss)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ArchivePalette.accentMoss.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.bottom, 8)

            Text(proj.title)
                .font(ArchiveTypography.editorialSerif(size: 16.5, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)

            if let sub = proj.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .padding(.top, 3)
                    .lineLimit(1)
            }

            if !proj.description.isEmpty {
                Text(LocalizedStringKey(proj.description))
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .lineLimit(3)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }

            Spacer(minLength: 12)

            Rectangle()
                .fill(ArchivePalette.borderDivider)
                .frame(height: 0.5)
                .padding(.vertical, 9)

            HStack {
                if let gh = proj.githubUrl, !gh.isEmpty, let url = URL(string: gh) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("源码仓库")
                        }
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    }
                } else {
                    Spacer(minLength: 0)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("修订项目")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(6)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("删除项目")
                }
            }
        }
        .padding(14)
        .frame(minHeight: 195)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.6)
        )
        .shadow(color: ArchivePalette.inkPrimary.opacity(0.04), radius: 6, x: 0, y: 2)
        .paperHover()
    }
}

// MARK: - 新建心愿单弹窗 (NewWishSheet)

@MainActor
public struct NewWishSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var kind: String = "item"
    @State private var budgetYuan: String = ""
    @State private var spec: String = ""
    @State private var note: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("许下新心愿")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 6) {
                PaperPillButton(title: "心仪好物", isSelected: kind == "item") { kind = "item" }
                PaperPillButton(title: "远方旅程", isSelected: kind == "travel") { kind = "travel" }
                PaperPillButton(title: "阶段里程碑", isSelected: kind == "milestone") { kind = "milestone" }
            }

            TextField("心愿名称（如：M3 MacBook Pro、苍山洱海自驾）", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("规格参数或目的地补充（可选）", text: $spec)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("预期预算金额（元，如 18999.00）", text: $budgetYuan)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 13))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("心愿初衷手记", text: $note)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("存入心愿单") {
                    submitWish()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(ArchivePalette.archivePaper)
    }

    private func submitWish() {
        let cents = FormatUtils.parseYuanToCents(budgetYuan) ?? 0
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateWishRequest(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: kind,
                    note: note.isEmpty ? nil : note,
                    spec: spec.isEmpty ? nil : spec,
                    budget: cents
                )
                _ = try await APIClient.shared.createWish(req)
                AudioFeedback.shared.playShutter()
                await appState.loadProjectsWishesFootprints()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 修订心愿弹窗 (EditWishSheet)

@MainActor
public struct EditWishSheet: View {
    @Bindable var appState: AppState
    let wish: Wish
    var onDismiss: () -> Void

    @State private var title: String
    @State private var kind: String
    @State private var budgetYuan: String
    @State private var spec: String
    @State private var note: String
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, wish: Wish, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.wish = wish
        self.onDismiss = onDismiss
        _title = State(initialValue: wish.title)
        _kind = State(initialValue: wish.kind)
        _budgetYuan = State(initialValue: FormatUtils.formattedYuan(cents: wish.budget))
        _spec = State(initialValue: wish.spec ?? "")
        _note = State(initialValue: wish.note ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("修订心愿")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 6) {
                PaperPillButton(title: "心仪好物", isSelected: kind == "item") { kind = "item" }
                PaperPillButton(title: "远方旅程", isSelected: kind == "travel") { kind = "travel" }
                PaperPillButton(title: "阶段里程碑", isSelected: kind == "milestone") { kind = "milestone" }
            }

            TextField("心愿名称", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("规格参数或目的地补充", text: $spec)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("意向预算金额（元）", text: $budgetYuan)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 13))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("初衷手记", text: $note)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存修改") {
                    updateWish()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(ArchivePalette.archivePaper)
    }

    private func updateWish() {
        let cents = FormatUtils.parseYuanToCents(budgetYuan) ?? 0
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateWishRequest(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: kind,
                    note: note.isEmpty ? nil : note,
                    spec: spec.isEmpty ? nil : spec,
                    budget: cents
                )
                _ = try await APIClient.shared.updateWish(id: wish.id, req)
                AudioFeedback.shared.playShutter()
                await appState.loadProjectsWishesFootprints()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 圆满心愿弹窗 (ResolveWishSheet)

@MainActor
public struct ResolveWishSheet: View {
    @Bindable var appState: AppState
    let wish: Wish
    var onDismiss: () -> Void

    @State private var actualCostYuan: String
    @State private var resolutionType: String = "exact" // exact | altered | relinquished
    @State private var createTransaction: Bool = true
    @State private var createGearAsset: Bool
    @State private var createLifeEntry: Bool = true
    @State private var createFootprint: Bool
    @State private var entryContent: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, wish: Wish, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.wish = wish
        self.onDismiss = onDismiss
        _actualCostYuan = State(initialValue: FormatUtils.formattedYuan(cents: wish.budget))
        _createGearAsset = State(initialValue: wish.kind == "item")
        _createFootprint = State(initialValue: wish.kind == "travel")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("圆满心愿 · 载入典藏")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text("达成目标：\(wish.title)")
                .font(ArchiveTypography.bodySans(size: 13, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)

            // 达成方式单选
            HStack(spacing: 6) {
                PaperPillButton(title: "如愿拿下", isSelected: resolutionType == "exact") { resolutionType = "exact" }
                PaperPillButton(title: "替代拿下", isSelected: resolutionType == "altered") { resolutionType = "altered" }
                PaperPillButton(title: "理性拔草", isSelected: resolutionType == "relinquished") { resolutionType = "relinquished" }
            }

            // 实付金额
            HStack(spacing: 4) {
                Text("实付金额 ¥")
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("0.00", text: $actualCostYuan)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                    .padding(6)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            // 联动联动伴生复选
            VStack(alignment: .leading, spacing: 8) {
                Toggle("联动生成一笔记账支出流水", isOn: $createTransaction)
                    .toggleStyle(.checkbox)
                    .font(ArchiveTypography.bodySans(size: 12))

                if wish.kind == "item" {
                    Toggle("联动建入随身固资设备库 (EDC Gear)", isOn: $createGearAsset)
                        .toggleStyle(.checkbox)
                        .font(ArchiveTypography.bodySans(size: 12))
                }

                if wish.kind == "travel" {
                    Toggle("同步点亮目的地城市足迹票根", isOn: $createFootprint)
                        .toggleStyle(.checkbox)
                        .font(ArchiveTypography.bodySans(size: 12))
                }

                Toggle("伴生发布一篇时间流手稿日记", isOn: $createLifeEntry)
                    .toggleStyle(.checkbox)
                    .font(ArchiveTypography.bodySans(size: 12))
            }

            if createLifeEntry {
                TextField("圆梦感言手记（如：寻觅良久，终得所愿…）", text: $entryContent)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("确认圆满归册") {
                    submitResolve()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(ArchivePalette.archivePaper)
    }

    private func submitResolve() {
        let isRelinquished = (resolutionType == "relinquished")
        let cents = isRelinquished ? 0 : (FormatUtils.parseYuanToCents(actualCostYuan) ?? 0)
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = ResolveWishRequest(
                    fulfilledAt: FormatUtils.beijingISOString(),
                    actualCost: cents,
                    resolutionType: resolutionType,
                    actualTitle: wish.title,
                    createTransaction: isRelinquished ? false : createTransaction,
                    createGearAsset: isRelinquished ? false : createGearAsset,
                    createLifeEntry: createLifeEntry,
                    createFootprint: isRelinquished ? false : createFootprint,
                    entryContent: entryContent.isEmpty ? nil : entryContent
                )
                _ = try await APIClient.shared.resolveWish(id: wish.id, req)
                AudioFeedback.shared.playShutter()
                await appState.loadProjectsWishesFootprints()
                await appState.loadEntries(forceFull: true)
                await appState.loadTransactionsAndAssets(forceFull: true)
                await appState.loadConfigAndProfile()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 点亮城市足迹弹窗 (NewFootprintSheet)

@MainActor
public struct NewFootprintSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var cityName: String = ""
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    private var resolvedCode: String {
        FormatUtils.resolveCityCode(from: cityName) ?? "330100"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("点亮城市行迹票根")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack {
                TextField("城市中文名称（如：大理市、苏州市、杭州）", text: $cityName)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if !cityName.isEmpty {
                    Text("代码: \(resolvedCode)")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            TextField("旅程标题（如：春日苍山洱海漫游，可选）", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("行迹随笔手记（可选）", text: $note)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("镌刻票根并伴生入流") {
                    submitFootprint()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(ArchivePalette.archivePaper)
    }

    private func submitFootprint() {
        let cleanCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCity.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateFootprintRequest(
                    cityCode: resolvedCode,
                    cityName: cleanCity,
                    title: title.isEmpty ? nil : title,
                    note: note.isEmpty ? nil : note
                )
                _ = try await APIClient.shared.createFootprint(req)
                AudioFeedback.shared.playShutter()
                await appState.loadProjectsWishesFootprints()
                await appState.loadEntries(forceFull: true)
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 修订足迹票根弹窗 (EditFootprintSheet)

@MainActor
public struct EditFootprintSheet: View {
    @Bindable var appState: AppState
    let footprint: Footprint
    var onDismiss: () -> Void

    @State private var cityName: String
    @State private var title: String
    @State private var note: String
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, footprint: Footprint, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.footprint = footprint
        self.onDismiss = onDismiss
        _cityName = State(initialValue: footprint.cityName)
        _title = State(initialValue: footprint.title ?? "")
        _note = State(initialValue: footprint.note ?? "")
    }

    private var resolvedCode: String {
        FormatUtils.resolveCityCode(from: cityName) ?? footprint.cityCode
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("修订行迹票根")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack {
                TextField("城市名称", text: $cityName)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text("代码: \(resolvedCode)")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            TextField("旅程标题", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("随笔手记", text: $note)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存票根修改") {
                    updateFootprint()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(ArchivePalette.archivePaper)
    }

    private func updateFootprint() {
        let cleanCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCity.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateFootprintRequest(
                    cityCode: resolvedCode,
                    cityName: cleanCity,
                    title: title.isEmpty ? nil : title,
                    visitedAt: footprint.visitedAt,
                    note: note.isEmpty ? nil : note
                )
                _ = try await APIClient.shared.updateFootprint(id: footprint.id, req)
                AudioFeedback.shared.playShutter()
                await appState.loadProjectsWishesFootprints()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 新建造物项目弹窗 (NewProjectSheet)

@MainActor
public struct NewProjectSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var description: String = ""
    @State private var category: String = "开源造物"
    @State private var status: String = "持续维护"
    @State private var githubUrl: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建造物与项目")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("项目名称（如：Loose-Leaf macOS 原生客户端）", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("副标题或一句话定义（可选）", text: $subtitle)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 8) {
                TextField("分类（如：开源造物、架构实验）", text: $category)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                TextField("状态（如：持续维护、稳定归档）", text: $status)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            TextField("项目详细背景与设计手记", text: $description)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("GitHub 源码仓库链接（可选）", text: $githubUrl)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 12))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("创建造物项目") {
                    submitProject()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(ArchivePalette.archivePaper)
    }

    private func submitProject() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateProjectRequest(
                    title: cleanTitle,
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    description: description,
                    category: category.isEmpty ? nil : category,
                    status: status.isEmpty ? nil : status,
                    githubUrl: githubUrl.isEmpty ? nil : githubUrl
                )
                _ = try await APIClient.shared.createProject(req)
                AudioFeedback.shared.playShutter()
                await appState.loadProjectsWishesFootprints()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 修订造物项目弹窗 (EditProjectSheet)

@MainActor
public struct EditProjectSheet: View {
    @Bindable var appState: AppState
    let project: Project
    var onDismiss: () -> Void

    @State private var title: String
    @State private var subtitle: String
    @State private var description: String
    @State private var category: String
    @State private var status: String
    @State private var githubUrl: String
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, project: Project, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.project = project
        self.onDismiss = onDismiss
        _title = State(initialValue: project.title)
        _subtitle = State(initialValue: project.subtitle ?? "")
        _description = State(initialValue: project.description)
        _category = State(initialValue: project.category ?? "开源造物")
        _status = State(initialValue: project.status ?? "持续维护")
        _githubUrl = State(initialValue: project.githubUrl ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("修订造物与项目")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("项目名称", text: $title)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("副标题或一句话定义", text: $subtitle)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 8) {
                TextField("分类", text: $category)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                TextField("状态", text: $status)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            TextField("项目详细背景手记", text: $description)
                .textFieldStyle(.plain)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            TextField("GitHub 源码仓库链接", text: $githubUrl)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 12))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存项目修改") {
                    updateProject()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(ArchivePalette.archivePaper)
    }

    private func updateProject() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateProjectRequest(
                    title: cleanTitle,
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    description: description,
                    category: category.isEmpty ? nil : category,
                    status: status.isEmpty ? nil : status,
                    githubUrl: githubUrl.isEmpty ? nil : githubUrl
                )
                _ = try await APIClient.shared.updateProject(id: project.id, req)
                AudioFeedback.shared.playShutter()
                await appState.loadProjectsWishesFootprints()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 山川经纬星野图谱 (CelestialAtlasCanvasView - RC-98)

@MainActor
public struct CelestialAtlasCanvasView: View {
    let footprints: [Footprint]
    var onSelectCity: (String, String) -> Void

    private struct CityCluster: Identifiable {
        var id: String { code }
        let code: String
        let name: String
        let count: Int
        let x: Double
        let y: Double
    }

    private var clusters: [CityCluster] {
        var map: [String: (name: String, count: Int)] = [:]
        for fp in footprints {
            let cur = map[fp.cityCode] ?? (name: fp.cityName, count: 0)
            map[fp.cityCode] = (name: fp.cityName, count: cur.count + 1)
        }
        return map.map { (code, info) in
            let pt = CityDictionary.coordinate(forCode: code, cityName: info.name)
            return CityCluster(code: code, name: info.name, count: info.count, x: pt.x, y: pt.y)
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Canvas { context, size in
                    let cols = 8
                    let rows = 5
                    for i in 1..<cols {
                        let x = size.width * CGFloat(i) / CGFloat(cols)
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(p, with: .color(ArchivePalette.borderDivider.opacity(0.6)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    }
                    for j in 1..<rows {
                        let y = size.height * CGFloat(j) / CGFloat(rows)
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(ArchivePalette.borderDivider.opacity(0.6)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    }
                }

                ForEach(clusters) { item in
                    let normX = CGFloat(min(max((item.x - 60.0) / 530.0, 0.05), 0.95))
                    let normY = CGFloat(min(max((item.y - 45.0) / 485.0, 0.08), 0.92))
                    let nodeColor = item.count >= 3 ? ArchivePalette.accentWarm : (item.count == 2 ? ArchivePalette.accentMoss : ArchivePalette.inkPrimary)

                    Button {
                        onSelectCity(item.code, item.name)
                    } label: {
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .fill(nodeColor.opacity(0.18))
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .fill(nodeColor)
                                    .frame(width: 7, height: 7)
                            }
                            Text(item.name)
                                .font(ArchiveTypography.editorialSerif(size: 11, weight: .medium))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(ArchivePalette.archivePaper.opacity(0.88))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: w * normX, y: h * normY)
                }

                // 右下角古典罗盘玫瑰 (Compass Rose) 与四角星野裁切标
                VStack(spacing: 1) {
                    Text("N")
                        .font(ArchiveTypography.editorialSerif(size: 10, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    Image(systemName: "safari")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(ArchivePalette.inkSecondary.opacity(0.65))
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CELESTIAL VOYAGE TOPOLOGY · 85°E — 125°E / 18°N — 50°N")
                        .font(ArchiveTypography.monoScale(size: 9.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Text("已点亮 \(clusters.count) 座城市 · 点击星芒打开城市回忆抽屉")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(height: 360)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderDivider, lineWidth: 0.7)
        )
    }
}

// MARK: - 城市回忆抽屉弹窗 (CityMemoryDrawerSheet)

@MainActor
public struct CityMemoryDrawerSheet: View {
    let cityCode: String
    let cityName: String
    var onDismiss: () -> Void

    @State private var drawer: CityMemoryDrawerResponse?
    @State private var isLoading: Bool = true
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(cityName) · 城市回忆抽屉")
                        .font(ArchiveTypography.editorialSerif(size: 18, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("行政代码 \(cityCode)")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                Button("关闭") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            if isLoading {
                ProgressView("正在翻找属地散页与相纸…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.accentWarm)
            } else if let d = drawer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("到访次数")
                                    .font(ArchiveTypography.bodySans(size: 11))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                Text("\(d.visitStats.totalVisits) 次")
                                    .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                            }
                            if !d.visitStats.firstVisitedAt.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("首访日期")
                                        .font(ArchiveTypography.bodySans(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(d.visitStats.firstVisitedAt)
                                        .font(ArchiveTypography.monoScale(size: 13))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                }
                            }
                            if d.ledgerSummary.totalSpent > 0 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("属地开销")
                                        .font(ArchiveTypography.bodySans(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(FormatUtils.formattedYuan(cents: d.ledgerSummary.totalSpent, includeSymbol: true))
                                        .font(ArchiveTypography.monoScale(size: 14, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                }
                            }
                        }

                        if !d.entries.isEmpty {
                            Text("属地散页随笔 (\(d.entries.count))")
                                .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            ForEach(d.entries) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(entry.title.isEmpty ? "散页手记" : entry.title)
                                            .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        Spacer()
                                        Text(entry.parsedDate.dotDate)
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                    }
                                    Text(entry.content)
                                        .font(ArchiveTypography.bodySans(size: 12))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .lineLimit(3)
                                }
                                .padding(10)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(ArchivePalette.archivePaper)
        .task {
            do {
                drawer = try await APIClient.shared.fetchCityMemoryDrawer(cityCode: cityCode)
                isLoading = false
            } catch {
                errorText = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - 年度生活年鉴五幕画卷弹窗 (AnnualAlmanacSheet)

@MainActor
public struct AnnualAlmanacSheet: View {
    var onDismiss: () -> Void

    @State private var selectedYear: Int = FormatUtils.beijingCurrentYearMonth().year
    @State private var almanac: AnnualAlmanacResponse?
    @State private var isLoading: Bool = true
    @State private var errorText: String?

    private var availableYears: [Int] {
        let currentYear = FormatUtils.beijingCurrentYearMonth().year
        let entryYears = AppState.shared.entries.compactMap { entry -> Int? in
            guard entry.occurredAt.count >= 4 else { return nil }
            return Int(entry.occurredAt.prefix(4))
        }
        let earliest = min(entryYears.min() ?? currentYear, currentYear)
        return Array((earliest...currentYear).reversed())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("《散页 · \(selectedYear) 年度生活年鉴》")
                        .font(ArchiveTypography.editorialSerif(size: 18, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("岁月卷首 · 山川行迹 · 心愿圆满 · 浮光掠影 · 柴米油盐")
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(availableYears, id: \.self) { yr in
                        PaperPillButton(title: "\(yr) 年", isSelected: selectedYear == yr) {
                            selectedYear = yr
                            Task { await loadAlmanac() }
                        }
                    }
                    Button("关闭") { onDismiss() }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            if isLoading {
                ProgressView("正在装订年度年鉴画卷…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.accentWarm)
            } else if let a = almanac {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 第一幕：岁月卷首
                        HStack(spacing: 20) {
                            almanacStat("散页篇幅", "\(a.prologue.totalEntries) 篇")
                            almanacStat("点亮城市", "\(a.prologue.citiesVisited) 城")
                            almanacStat("圆满心愿", "\(a.prologue.wishesFulfilled) 愿")
                            almanacStat("记账笔数", "\(a.prologue.txCount) 笔")
                        }
                        .padding(12)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        // 第二幕：山川行迹
                        if !a.atlas.cities.isEmpty {
                            Text("第二幕 · 山川行迹 (\(a.atlas.totalCities) 城)")
                                .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                            Text(a.atlas.cities.map(\.cityName).joined(separator: " · "))
                                .font(ArchiveTypography.bodySans(size: 12.5))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                        }

                        // 第三幕：心愿圆满
                        Text("第三幕 · 心愿圆满 (已达成 \(a.wishes.fulfilledCount) / 在愿 \(a.wishes.wantingCount))")
                            .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))

                        // 第五幕：柴米油盐
                        if a.finances.totalExpense > 0 || a.finances.totalIncome > 0 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("第五幕 · 柴米油盐")
                                    .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                                HStack(spacing: 18) {
                                    Text("总支出 \(FormatUtils.formattedYuan(cents: a.finances.totalExpense, includeSymbol: true))")
                                        .font(ArchiveTypography.monoScale(size: 12))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                    Text("总收入 \(FormatUtils.formattedYuan(cents: a.finances.totalIncome, includeSymbol: true))")
                                        .font(ArchiveTypography.monoScale(size: 12))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                    Text(String(format: "取悦自己占比 %.1f%%", a.finances.wishSpendingRatio))
                                        .font(ArchiveTypography.monoScale(size: 12))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(ArchivePalette.archivePaper)
        .task {
            await loadAlmanac()
        }
    }

    private func almanacStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(ArchiveTypography.bodySans(size: 11))
                .foregroundStyle(ArchivePalette.inkMuted)
            Text(value)
                .font(ArchiveTypography.monoScale(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
        }
    }

    private func loadAlmanac() async {
        isLoading = true
        errorText = nil
        do {
            almanac = try await APIClient.shared.fetchAnnualAlmanac(year: selectedYear)
            isLoading = false
        } catch {
            errorText = error.localizedDescription
            isLoading = false
        }
    }
}
