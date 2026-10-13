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

    // 足迹票根状态
    @State private var showNewFootprintSheet: Bool = false
    @State private var editingFootprint: Footprint?

    // 造物项目状态
    @State private var showNewProjectSheet: Bool = false
    @State private var editingProject: Project?

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
                        Text("二级投影均与主时间流伴生联动 · 主理人全权管理")
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

                            // 主理人操作栏
                            HStack(spacing: 8) {
                                if wish.status != "fulfilled" {
                                    Button("圆满心愿") {
                                        resolvingWish = wish
                                    }
                                    .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(ArchivePalette.accentMoss)
                                }

                                Spacer()

                                Button {
                                    editingWish = wish
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)
                                .help("修订心愿")

                                Button {
                                    deleteWish(wish)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)
                                .help("删除心愿")
                            }
                            .padding(.top, 4)
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
                                        deleteFootprint(fp)
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
                                }

                                Spacer()

                                Button {
                                    editingProject = proj
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)
                                .help("修订项目")

                                Button {
                                    deleteProject(proj)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)
                                .help("删除项目")
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
    @State private var entryContent: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, wish: Wish, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.wish = wish
        self.onDismiss = onDismiss
        _actualCostYuan = State(initialValue: FormatUtils.formattedYuan(cents: wish.budget))
        _createGearAsset = State(initialValue: wish.kind == "item")
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
        let cents = FormatUtils.parseYuanToCents(actualCostYuan) ?? 0
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = ResolveWishRequest(
                    fulfilledAt: FormatUtils.beijingISOString(),
                    actualCost: cents,
                    resolutionType: resolutionType,
                    actualTitle: wish.title,
                    createTransaction: createTransaction,
                    createGearAsset: createGearAsset,
                    createLifeEntry: createLifeEntry,
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

/// 主理人生活手记与器物图鉴视图 (CuratorDossierView)
/// 严格遵守：100% 由 GET /api/v1/profile 动态驱动，严禁硬编码姓名或城市
@MainActor
public struct CuratorDossierView: View {
    @Bindable var appState: AppState

    @State private var showEditProfileSheet: Bool = false
    @State private var sellingGear: GearItem?
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
                        Text("尚无随身器物记录。在资产中枢中添置设备后将自动同步展示。")
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

                                    HStack {
                                        if let price = gear.priceCents, price > 0 {
                                            Text("购入 \(FormatUtils.formattedYuan(cents: price, includeSymbol: true))")
                                                .font(ArchiveTypography.monoScale(size: 11))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                        }

                                        if let sold = gear.soldPriceCents, sold > 0 {
                                            Text("回血 \(FormatUtils.formattedYuan(cents: sold, includeSymbol: true))")
                                                .font(ArchiveTypography.monoScale(size: 11))
                                                .foregroundStyle(ArchivePalette.accentMoss)
                                        }

                                        Spacer()

                                        if gear.status != "sold" {
                                            Button("转让回血") {
                                                sellingGear = gear
                                            }
                                            .font(ArchiveTypography.bodySans(size: 10.5))
                                            .buttonStyle(.plain)
                                            .foregroundStyle(ArchivePalette.accentWarm)
                                        }

                                        Button {
                                            deleteGear(gear)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(ArchivePalette.inkMuted)
                                        }
                                        .buttonStyle(.plain)
                                        .help("删除设备")
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
        .sheet(item: $sellingGear) { gear in
            SellGearSheet(gear: gear) {
                sellingGear = nil
            } onSold: {
                Task { @MainActor in
                    await appState.loadConfigAndProfile()
                    await appState.loadTransactionsAndAssets(forceFull: true)
                }
            }
        }
    }

    private func deleteGear(_ gear: GearItem) {
        Task { @MainActor in
            try? await APIClient.shared.deleteGearAsset(id: gear.id)
            AudioFeedback.shared.playTink()
            await appState.loadConfigAndProfile()
            await appState.loadTransactionsAndAssets(forceFull: true)
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
                    Task { @MainActor in
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
