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
    @State private var selectedStatus: String = "all" // all, Active, Archived

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
            let status = p.status ?? "active"
            let matchStatus = (selectedStatus == "all") || (status.caseInsensitiveCompare(selectedStatus) == .orderedSame)
            return matchCat && matchStatus
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                filterPillsSection

                if let err = errorMessage {
                    Text(err)
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }

                if filteredProjects.isEmpty {
                    emptyPlaceholder
                } else {
                    projectsGridSection
                }
            }
            .padding(24)
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
                HStack(spacing: 8) {
                    Text("造物项目")
                        .font(ArchiveTypography.editorialSerif(size: 24, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("人生经历与实践章节")
                        .font(ArchiveTypography.monoScale(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Text("手艺与造物 · 软件架构实验、开源工具与生活工坊方案陈列")
                    .font(ArchiveTypography.editorialSerif(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }

            Spacer()

            Button {
                showNewProjectSheet = true
                AudioFeedback.shared.playTink()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "hammer")
                        .font(.system(size: 11, weight: .medium))
                    Text("立项新造物")
                        .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
        }
    }

    // MARK: - 2. 筛选胶囊
    private var filterPillsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                PaperPillButton(title: "全部造物 (\(allProjects.count))", isSelected: selectedCategory == "all") {
                    guard selectedCategory != "all" else { return }
                    selectedCategory = "all"
                    AudioFeedback.shared.playTink()
                }

                ForEach(categories, id: \.self) { cat in
                    let count = allProjects.filter { $0.category == cat }.count
                    PaperPillButton(title: "\(cat) (\(count))", isSelected: selectedCategory == cat) {
                        guard selectedCategory != cat else { return }
                        selectedCategory = cat
                        AudioFeedback.shared.playTink()
                    }
                }
            }

            HStack(spacing: 6) {
                PaperPillButton(title: "全状态", isSelected: selectedStatus == "all") {
                    selectedStatus = "all"
                }
                PaperPillButton(title: "进行中 (Active)", isSelected: selectedStatus == "Active") {
                    selectedStatus = "Active"
                }
                PaperPillButton(title: "已归档 (Archived)", isSelected: selectedStatus == "Archived") {
                    selectedStatus = "Archived"
                }
            }
        }
    }

    // MARK: - 3. 项目网格与进展手记
    private var projectsGridSection: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
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
                    let projectEntries = appState.entries.filter { $0.projectId == proj.id }
                    if !projectEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
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
                                .font(ArchiveTypography.monoScale(size: 10))
                                .buttonStyle(.plain)
                                .foregroundStyle(ArchivePalette.accentWarm)
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 8)

                            ForEach(projectEntries.prefix(3)) { entry in
                                HStack(spacing: 6) {
                                    Text(FormatUtils.parseOccurredDate(entry.occurredAt).dotDate)
                                        .font(ArchiveTypography.monoScale(size: 10))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                    Text(entry.title.isEmpty ? entry.content : entry.title)
                                        .font(ArchiveTypography.bodySans(size: 11))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                            }
                        }
                        .padding(.bottom, 12)
                    }
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

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Text("该分类下尚无造物项目")
                .font(ArchiveTypography.editorialSerif(size: 14, weight: .medium))
                .foregroundStyle(ArchivePalette.inkSecondary)
            Text("点击右上角「立项新造物」，记录您的独立开发、开源构想或生活手作")
                .font(ArchiveTypography.bodySans(size: 11.5))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func deleteProject(_ proj: Project) {
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteProject(id: proj.id)
                AudioFeedback.shared.playTink()
                await appState.loadProjectsWishesFootprints()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
