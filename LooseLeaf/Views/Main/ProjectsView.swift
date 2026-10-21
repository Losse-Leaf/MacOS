import SwiftUI

/// 造物项目独立主视图 (ProjectsView)
/// 严格 1:1 对标 Web 端 `web/src/components/ProjectsView.vue`：
/// 1. 标头：“造物项目 · 人生经历与实践章节” + “立项新项目”入口
/// 2. 分类标签胶囊（开源项目/独立开发/硬件手作/写作出版等）与活跃/归档状态过滤
/// 3. 项目陈列网格与编年进展手记瀑布流
/// 4. 项目立项与编辑模态弹窗 (NewProjectSheet / EditProjectSheet)
@MainActor
public struct ProjectsView: View {
    @Bindable var appState: AppState

    @State private var selectedCategory: String = "all"
    @State private var selectedStatus: String = "all" // all, ProjectStatus.active.rawValue, ProjectStatus.archived.rawValue

    @State private var showNewProjectSheet: Bool = false
    @State private var editingProject: Project?
    @State private var errorMessage: String?

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
            // 状态匹配统一走 ProjectStatus 语义字典，兼容历史数据中的「持续维护」等表述
            let matchStatus = ProjectStatus.matches(p.status, selected: selectedStatus)
            return matchCat && matchStatus
        }
    }

    /// 分类 → 项目数量（预先统计，避免在 ForEach 体内重复全量扫描）
    private var categoryCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for project in allProjects {
            guard let cat = project.category, !cat.isEmpty else { continue }
            counts[cat, default: 0] += 1
        }
        return counts
    }

    /// 项目 ID → 关联进展手记（预先建立索引，避免每张卡片触发一次全量过滤）
    /// 未归属项目的散页归入 -1 桶，不参与任何项目的进展展示。
    private var entriesByProjectId: [Int: [LifeEntry]] {
        Dictionary(grouping: appState.entries, by: { $0.projectId ?? -1 })
    }

    public var body: some View {
        // 一次性绑定统计结果，避免同一份扫描在 body 内被重复触发
        let counts = categoryCounts
        let entriesIndex = entriesByProjectId

        ScrollView {
            // LazyVStack 作为 ScrollView 直接子视图，长列表才具备懒加载能力
            LazyVStack(alignment: .leading, spacing: ArchiveSpacing.xl) {
                headerSection

                filterPillsSection(counts: counts)

                if let err = errorMessage {
                    Text(err)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                if appState.isLoading {
                    // 加载中：与「真的为空」区分，避免用户误以为数据丢失
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

            HStack(spacing: 6) {
                PaperPillButton(title: "全状态", isSelected: selectedStatus == "all") {
                    selectedStatus = "all"
                }
                // 状态取值与 ProjectStatus 语义字典保持一致，新建的项目方可被正确筛出
                PaperPillButton(title: "进行中 (\(ProjectStatus.active.rawValue))", isSelected: selectedStatus == ProjectStatus.active.rawValue) {
                    selectedStatus = ProjectStatus.active.rawValue
                }
                PaperPillButton(title: "已归档 (\(ProjectStatus.archived.rawValue))", isSelected: selectedStatus == ProjectStatus.archived.rawValue) {
                    selectedStatus = ProjectStatus.archived.rawValue
                }
            }
        }
    }

    // MARK: - 3. 项目网格与进展手记
    private func projectsGridSection(entriesIndex: [Int: [LifeEntry]]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: ArchiveCardMetrics.padding), GridItem(.flexible(), spacing: ArchiveCardMetrics.padding)], spacing: ArchiveCardMetrics.padding) {
            ForEach(filteredProjects) { proj in
                VStack(alignment: .leading, spacing: 0) {
                    ProjectCardView(
                        proj: proj,
                        onEdit: {
                            editingProject = proj
                        },
                        onDelete: {
                            appState.askConfirm(
                                title: "确认删除该造物项目？",
                                message: "删除后将移除该项目档案，关联的历史进展散页不会被删除。",
                                confirmText: "删除项目",
                                danger: true
                            ) {
                                deleteProject(proj)
                            }
                        }
                    )

                    // 项目下属编年手记流预览
                    let projectEntries = entriesIndex[proj.id] ?? []
                    if !projectEntries.isEmpty {
                        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
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
                            }
                            .padding(.horizontal, ArchiveCardMetrics.padding)
                            .padding(.top, 8)

                            ForEach(projectEntries.prefix(3)) { entry in
                                HStack(spacing: 6) {
                                    Text(FormatUtils.parseOccurredDate(entry.occurredAt).dotDate)
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(entry.title.isEmpty ? entry.content : entry.title)
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, ArchiveCardMetrics.padding)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
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
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteProject(id: proj.id)
                // 造物的伴生散页要一并从时间流移除
                await appState.refreshAfterSecondaryWrite()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 预览 (Preview)

#Preview("造物项目") {
    ProjectsView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}
