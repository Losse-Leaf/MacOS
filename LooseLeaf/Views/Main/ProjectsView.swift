import SwiftUI

/// 仅供 `ProjectsView` 按 `contentRevision` 缓存关联进展散页索引（避免每次 body 求值全量分组 5000+ 无关散页）
@MainActor
private final class ProjectEntriesIndexMemo {
    var revision: Int = -1
    var map: [Int: [LifeEntry]] = [:]

    func index(for entries: [LifeEntry], revision: Int) -> [Int: [LifeEntry]] {
        if self.revision == revision {
            return map
        }
        var grouped: [Int: [LifeEntry]] = [:]
        for entry in entries {
            guard let pid = entry.projectId, (entry.deletedAt ?? "").isEmpty else { continue }
            grouped[pid, default: []].append(entry)
        }
        self.revision = revision
        self.map = grouped
        return grouped
    }
}

/// 造物项目独立主视图 (ProjectsView)
/// 1. 标头：“造物项目 · 人生经历与实践章节” + “立项新造物”入口
/// 2. 分类标签胶囊与四态状态筛选
/// 3. 项目陈列网格与可点击阅读的编年进展手记预览（支持 ⌘K 精准定位与 ⌘Z 撤销删除）
@MainActor
public struct ProjectsView: View {
    @Bindable var appState: AppState

    @State private var selectedCategory: String = "all"
    @State private var selectedStatus: String = "all"

    @State private var showNewProjectSheet: Bool = false
    @State private var editingProject: Project?
    @State private var errorMessage: String?
    @State private var highlightedId: Int?
    @State private var entriesMemo = ProjectEntriesIndexMemo()

    public init(appState: AppState) {
        self.appState = appState
    }

    private var allProjects: [Project] {
        appState.projects
    }

    private var categories: [String] {
        var set = Set<String>()
        for p in allProjects {
            if let cat = p.category, !cat.isEmpty {
                set.insert(cat)
            }
        }
        for c in appState.projectCategories {
            set.insert(c)
        }
        return Array(set).sorted()
    }

    private var filteredProjects: [Project] {
        allProjects.filter { p in
            let matchCat = (selectedCategory == "all") || (p.category == selectedCategory)
            let matchStatus = ProjectStatus.matches(p.status, selected: selectedStatus)
            return matchCat && matchStatus
        }
    }

    private var categoryCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for project in allProjects {
            guard let cat = project.category, !cat.isEmpty else { continue }
            counts[cat, default: 0] += 1
        }
        return counts
    }

    public var body: some View {
        let counts = categoryCounts
        let entriesIndex = entriesMemo.index(for: appState.entries, revision: appState.contentRevision)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ArchiveSpacing.xl) {
                    headerSection

                    filterPillsSection(counts: counts)

                    if let err = errorMessage {
                        Text(err)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }

                    if appState.isLoading && allProjects.isEmpty {
                        ProgressView("正在誊写造物项目档案…")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if filteredProjects.isEmpty {
                        emptyPlaceholder
                    } else {
                        projectsGridSection(entriesIndex: entriesIndex)
                    }
                }
                .padding(ArchiveSpacing.xl)
            }
            .onAppear {
                consumeHighlightedProjectIfNeeded(proxy: proxy)
            }
            .onChange(of: appState.navigation.highlightedProjectId) { _, _ in
                consumeHighlightedProjectIfNeeded(proxy: proxy)
            }
        }
        .sheet(isPresented: $showNewProjectSheet) {
            ProjectEditorSheet(appState: appState) {
                showNewProjectSheet = false
            }
        }
        .sheet(item: $editingProject) { proj in
            ProjectEditorSheet(appState: appState, project: proj) {
                editingProject = nil
            }
        }
    }

    private func consumeHighlightedProjectIfNeeded(proxy: ScrollViewProxy) {
        guard let targetId = appState.navigation.highlightedProjectId else { return }
        selectedCategory = "all"
        selectedStatus = "all"
        highlightedId = targetId
        appState.navigation.highlightedProjectId = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(ArchiveMotion.standard) {
                proxy.scrollTo(targetId, anchor: .center)
            }
            try? await Task.sleep(for: .seconds(2.4))
            if highlightedId == targetId {
                highlightedId = nil
            }
        }
    }

    // MARK: - 1. 标头
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: ArchiveSpacing.s) {
                    Text("造物项目")
                        .font(ArchiveTypography.editorialSerif(size: 24, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("人生经历与实践章节")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Text("手艺与造物 · 软件架构实验、开源工具与生活工坊方案陈列")
                    .font(ArchiveTypography.editorialSerif(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }

            Spacer()

            Button {
                showNewProjectSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "hammer")
                        .font(.system(size: 11, weight: .medium))
                    Text("立项新造物")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
        }
    }

    // MARK: - 2. 筛选胶囊
    private func filterPillsSection(counts: [String: Int]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    PaperPillButton(title: "全部造物 (\(allProjects.count))", isSelected: selectedCategory == "all") {
                        guard selectedCategory != "all" else { return }
                        selectedCategory = "all"
                    }

                    ForEach(categories, id: \.self) { cat in
                        let count = counts[cat] ?? 0
                        PaperPillButton(title: "\(cat) (\(count))", isSelected: selectedCategory == cat) {
                            guard selectedCategory != cat else { return }
                            selectedCategory = cat
                        }
                    }
                }
            }
            .horizontalFadeMask()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    PaperPillButton(title: "全状态", isSelected: selectedStatus == "all") {
                        selectedStatus = "all"
                    }
                    ForEach(ProjectStatus.allCases) { st in
                        PaperPillButton(title: st.displayName, isSelected: selectedStatus == st.rawValue) {
                            selectedStatus = st.rawValue
                        }
                    }
                }
            }
            .horizontalFadeMask()
        }
    }

    // MARK: - 3. 项目网格与进展手记
    private func projectsGridSection(entriesIndex: [Int: [LifeEntry]]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: ArchiveCardMetrics.padding), GridItem(.flexible(), spacing: ArchiveCardMetrics.padding)], spacing: ArchiveCardMetrics.padding) {
            ForEach(filteredProjects) { proj in
                VStack(alignment: .leading, spacing: 0) {
                    ProjectCardView(
                        proj: proj,
                        isHighlighted: highlightedId == proj.id,
                        onEdit: {
                            editingProject = proj
                        },
                        onDelete: {
                            appState.askConfirm(
                                title: "确认删除该造物项目？",
                                message: "删除后将移除该项目档案，关联的历史进展散页不会被删除，可按 ⌘Z 撤销。",
                                confirmText: "删除项目",
                                danger: true
                            ) {
                                deleteProject(proj)
                            }
                        }
                    )

                    let projectEntries = entriesIndex[proj.id] ?? []
                    if !projectEntries.isEmpty {
                        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                            HStack {
                                Text("进展手记 (\(projectEntries.count))")
                                    .font(ArchiveTypography.monoScale(size: 10.5))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                                Spacer()
                                Button("+ 追加手记") {
                                    appState.newEntryInitialProjectId = proj.id
                                    appState.newEntryInitialKind = "project"
                                    appState.showNewEntrySheet = true
                                }
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                .buttonStyle(.plain)
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                            }
                            .padding(.horizontal, ArchiveCardMetrics.padding)
                            .padding(.top, 8)

                            ForEach(projectEntries.prefix(3)) { entry in
                                Button {
                                    appState.highlightedEntry = entry
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(entry.parsedDate.dotDate)
                                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                        Text(entry.title.isEmpty ? entry.content : entry.title)
                                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8.5, weight: .semibold))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                    }
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .paperHover()
                                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                                .padding(.horizontal, ArchiveCardMetrics.padding - 6)
                            }
                        }
                        .padding(.bottom, 10)
                    }
                }
                .id(proj.id)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .stroke(
                            highlightedId == proj.id ? ArchivePalette.accentWarm : ArchivePalette.borderDivider,
                            lineWidth: highlightedId == proj.id ? 1.5 : 0.5
                        )
                )
            }
        }
    }

    private var emptyPlaceholder: some View {
        ArchiveEmptyState(
            systemName: ArchiveIcon.projects.systemName,
            title: "该分类下尚无造物项目",
            message: "点击右上角「立项新造物」，记录您的独立开发、开源构想或生活手作。",
            primaryTitle: "立项新造物",
            primaryAction: { showNewProjectSheet = true }
        )
        .frame(minHeight: 180)
    }

    private func deleteProject(_ proj: Project) {
        errorMessage = nil
        Task { @MainActor in
            do {
                try await appState.deleteProjectAction(proj)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if DEBUG
#Preview("造物项目") {
    ProjectsView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}
#endif
