import SwiftUI

/// 统一造物项目新建与修订弹窗 (ProjectEditorSheet)
/// - `project == nil`：立项新造物（可选字段为空时传 `nil`）
/// - `project != nil`：修订既有造物（保留 `order` 排序，空串显式透传给指针语义接口以支持清空）
@MainActor
public struct ProjectEditorSheet: View {
    @Bindable var appState: AppState
    let project: Project?
    var onDismiss: () -> Void

    @State private var title: String
    @State private var subtitle: String
    @State private var description: String
    @State private var story: String
    @State private var category: String
    @State private var status: String
    @State private var githubUrl: String
    @State private var isPrivate: Bool
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    @FocusState private var isTitleFocused: Bool

    public init(appState: AppState, project: Project? = nil, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.project = project
        self.onDismiss = onDismiss
        if let project {
            _title = State(initialValue: project.title)
            _subtitle = State(initialValue: project.subtitle ?? "")
            _description = State(initialValue: project.description)
            _story = State(initialValue: project.story ?? "")
            _category = State(initialValue: project.category ?? appState.projectCategories.first ?? "开源项目")
            _status = State(initialValue: ProjectStatus.normalize(project.status).rawValue)
            _githubUrl = State(initialValue: project.githubUrl ?? "")
            _isPrivate = State(initialValue: project.isPrivate ?? false)
        } else {
            _title = State(initialValue: "")
            _subtitle = State(initialValue: "")
            _description = State(initialValue: "")
            _story = State(initialValue: "")
            _category = State(initialValue: appState.projectCategories.first ?? "开源项目")
            _status = State(initialValue: ProjectStatus.inProgress.rawValue)
            _githubUrl = State(initialValue: "")
            _isPrivate = State(initialValue: false)
        }
    }

    private var isEditing: Bool { project != nil }

    private var categoryOptions: [PaperSelectOption<String>] {
        let base = appState.projectCategories.contains(category) || category.isEmpty
            ? appState.projectCategories
            : ([category] + appState.projectCategories)
        return base.map { PaperSelectOption(value: $0, label: $0) }
    }

    public var body: some View {
        PaperSheetScaffold(
            title: isEditing ? "修订造物与项目" : "新建造物与项目",
            subtitle: isEditing ? nil : "人生经历与实践章节",
            width: ArchiveSheetWidth.standard,
            isSubmitting: isSubmitting,
            isSubmitDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            submitTitle: isEditing ? "保存项目修改 ⌘↩" : "创建造物项目 ⌘↩",
            onCancel: onDismiss,
            onSubmit: submit
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                TextField("项目名称", text: $title)
                    .accessibilityLabel("项目名称")
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("副标题或一句话定义", text: $subtitle)
                    .accessibilityLabel("项目副标题")
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                HStack(spacing: ArchiveSpacing.s) {
                    PaperSelect(
                        selection: $category,
                        options: categoryOptions,
                        label: "项目类型："
                    )
                }

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

                TextField("项目详细背景与设计手记", text: $description, axis: .vertical)
                    .accessibilityLabel("项目详细背景与设计手记")
                    .textFieldStyle(.plain)
                    .lineLimit(2...6)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                VStack(alignment: .leading, spacing: 4) {
                    Text("项目故事")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    TextField("写下一段关于这个造物的故事…", text: $story, axis: .vertical)
                        .accessibilityLabel("项目故事")
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.body))
                        .lineLimit(4...10)
                        .padding(ArchiveSpacing.s)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                TextField("GitHub 源码仓库链接", text: $githubUrl)
                    .accessibilityLabel("源码仓库链接")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                HStack {
                    Label("私密项目（仅配对主理人设备可见）", systemImage: ArchiveIcon.lock.systemName)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Spacer()
                    Toggle("私密项目", isOn: $isPrivate)
                        .labelsHidden()
                        .toggleStyle(.paperSwitch)
                        .accessibilityLabel("设为私密项目")
                }

                if let errorText {
                    Text(errorText)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
            }
        }
        .onAppear {
            isTitleFocused = true
        }
    }

    private func submit() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                if let project {
                    let req = CreateProjectRequest(
                        title: cleanTitle,
                        subtitle: subtitle,
                        description: description,
                        story: story,
                        category: category.isEmpty ? nil : category,
                        status: status.isEmpty ? nil : status,
                        githubUrl: githubUrl,
                        order: project.order,
                        isPrivate: isPrivate
                    )
                    _ = try await APIClient.shared.updateProject(id: project.id, req)
                } else {
                    let req = CreateProjectRequest(
                        title: cleanTitle,
                        subtitle: subtitle.isEmpty ? nil : subtitle,
                        description: description,
                        story: story.isEmpty ? nil : story,
                        category: category.isEmpty ? nil : category,
                        status: status.isEmpty ? nil : status,
                        githubUrl: githubUrl.isEmpty ? nil : githubUrl,
                        isPrivate: isPrivate
                    )
                    _ = try await APIClient.shared.createProject(req)
                }
                await appState.refreshAfterSecondaryWrite()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
