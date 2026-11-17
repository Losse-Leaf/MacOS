import SwiftUI

/// 造物项目相关弹窗集合 (NewProjectSheet / EditProjectSheet)
/// 1. NewProjectSheet —— 新建造物与项目（分类 / 状态语义 / 私密开关 / GitHub 仓库）
/// 2. EditProjectSheet —— 修订既有造物项目（连带刷新伴生散页）

// MARK: - 新建造物项目弹窗 (NewProjectSheet)

@MainActor
public struct NewProjectSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var description: String = ""
    @State private var story: String = ""
    @State private var category: String
    @State private var status: String = ProjectStatus.inProgress.rawValue
    @State private var githubUrl: String = ""
    @State private var isPrivate: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    @FocusState private var isTitleFocused: Bool

    public init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
        _category = State(initialValue: appState.projectCategories.first ?? "开源项目")
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "新建造物与项目",
            subtitle: "人生经历与实践章节",
            width: ArchiveSheetWidth.standard,
            isSubmitting: isSubmitting,
            isSubmitDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            submitTitle: "创建造物项目 ⌘↩",
            onCancel: onDismiss,
            onSubmit: submitProject
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                TextField("项目名称", text: $title)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("副标题或一句话定义", text: $subtitle)
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                HStack(spacing: ArchiveSpacing.s) {
                    PaperSelect(
                        selection: $category,
                        options: appState.projectCategories.map { PaperSelectOption(value: $0, label: $0) },
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

    private func submitProject() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
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
                await appState.refreshAfterSecondaryWrite()
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
    @State private var story: String
    @State private var category: String
    @State private var status: String
    @State private var githubUrl: String
    @State private var isPrivate: Bool
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    @FocusState private var isTitleFocused: Bool

    public init(appState: AppState, project: Project, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.project = project
        self.onDismiss = onDismiss
        _title = State(initialValue: project.title)
        _subtitle = State(initialValue: project.subtitle ?? "")
        _description = State(initialValue: project.description)
        _story = State(initialValue: project.story ?? "")
        _category = State(initialValue: project.category ?? appState.projectCategories.first ?? "开源项目")
        _status = State(initialValue: ProjectStatus.normalize(project.status).rawValue)
        _githubUrl = State(initialValue: project.githubUrl ?? "")
        _isPrivate = State(initialValue: project.isPrivate ?? false)
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "修订造物与项目",
            width: ArchiveSheetWidth.standard,
            isSubmitting: isSubmitting,
            isSubmitDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            submitTitle: "保存项目修改 ⌘↩",
            onCancel: onDismiss,
            onSubmit: updateProject
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                TextField("项目名称", text: $title)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("副标题或一句话定义", text: $subtitle)
                    .textFieldStyle(.plain)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                HStack(spacing: ArchiveSpacing.s) {
                    PaperSelect(
                        selection: $category,
                        options: (appState.projectCategories.contains(category)
                                   ? appState.projectCategories
                                   : ([category] + appState.projectCategories)
                        ).map { PaperSelectOption(value: $0, label: $0) },
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

                TextField("项目详细背景手记", text: $description, axis: .vertical)
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

    private func updateProject() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
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
                await appState.refreshAfterSecondaryWrite()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
