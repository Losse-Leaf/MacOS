import SwiftUI

/// 造物项目相关弹窗集合 (NewProjectSheet / EditProjectSheet)
/// 从 ProjectsWishesView 中拆出的独立 Sheet 组件：
/// 1. NewProjectSheet —— 新建造物与项目（分类 / 状态语义 / GitHub 仓库）
/// 2. EditProjectSheet —— 修订既有造物项目
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

// MARK: - 新建造物项目弹窗 (NewProjectSheet)

@MainActor
public struct NewProjectSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var description: String = ""
    @State private var category: String = "开源造物"
    // 默认状态与 ProjectsView 的状态筛选共用同一套语义常量（进行中 = "Active"）
    @State private var status: String = ProjectStatus.active.rawValue
    @State private var githubUrl: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            Text("新建造物与项目")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("项目名称", text: $title)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("副标题或一句话定义", text: $subtitle)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            HStack(spacing: ArchiveSpacing.s) {
                TextField("分类", text: $category)
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("状态", text: $status)
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            }

            // 状态快选：与 ProjectsView 的筛选胶囊共用同一套语义常量
            HStack(spacing: 6) {
                Text("状态快选：")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                ForEach(ProjectStatus.allCases) { st in
                    PaperPillButton(title: st.displayName, isSelected: status == st.rawValue) {
                        status = st.rawValue
                    }
                }
            }

            TextField("项目详细背景与设计手记", text: $description)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("GitHub 源码仓库链接", text: $githubUrl)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

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
        .frame(
            minWidth: ArchiveSheetWidth.standard,
            idealWidth: ArchiveSheetWidth.standard,
            maxWidth: ArchiveSheetWidth.standard
        )
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
        _status = State(initialValue: project.status ?? ProjectStatus.active.rawValue)
        _githubUrl = State(initialValue: project.githubUrl ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            Text("修订造物与项目")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("项目名称", text: $title)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("副标题或一句话定义", text: $subtitle)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            HStack(spacing: ArchiveSpacing.s) {
                TextField("分类", text: $category)
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("状态", text: $status)
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            }

            // 状态快选：与 ProjectsView 的筛选胶囊共用同一套语义常量
            HStack(spacing: 6) {
                Text("状态快选：")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                ForEach(ProjectStatus.allCases) { st in
                    PaperPillButton(title: st.displayName, isSelected: status == st.rawValue) {
                        status = st.rawValue
                    }
                }
            }

            TextField("项目详细背景手记", text: $description)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("GitHub 源码仓库链接", text: $githubUrl)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

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
        .frame(
            minWidth: ArchiveSheetWidth.standard,
            idealWidth: ArchiveSheetWidth.standard,
            maxWidth: ArchiveSheetWidth.standard
        )
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
                await appState.loadProjectsWishesFootprints()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
