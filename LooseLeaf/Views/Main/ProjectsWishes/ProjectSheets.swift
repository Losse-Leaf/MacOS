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
    /// 项目故事（设计手记）—— 后端与 Web 端早已支持，桌面端本轮补齐（MC-04）
    @State private var story: String = ""
    @State private var category: String = "开源造物"
    // 默认状态与 ProjectsView 的状态筛选共用同一套语义常量（进行中 = "Active"）
    @State private var status: String = ProjectStatus.inProgress.rawValue
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
                // 项目类型是**选择**而非手填：选项来自后端动态分类字典
                PaperSelect(
                    selection: $category,
                    options: appState.projectCategories.map { PaperSelectOption(value: $0, label: $0) },
                    label: "项目类型："
                )
                // 关键（2026-10-25 修复）：状态只走下方快选胶囊，**删除手填框** ——
                // 原先自由文本与快选胶囊同写一个字段，手填任意值后端无白名单照单全收，
                // 展示层归一不到枚举的值会被静默改写显示（跨端分叉）。
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

            // 项目故事：多行、纸质、斜体排印 —— 与「详细背景」区分开
            VStack(alignment: .leading, spacing: 4) {
                Text("项目故事")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("写下一段关于这个造物的故事…", text: $story, axis: .vertical)
                    .accessibilityLabel("项目故事")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.body))
                    .lineLimit(3...6)
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

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                Spacer()
                Button("创建造物项目") {
                    submitProject()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
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
                    story: story.isEmpty ? nil : story,
                    category: category.isEmpty ? nil : category,
                    status: status.isEmpty ? nil : status,
                    githubUrl: githubUrl.isEmpty ? nil : githubUrl
                )
                _ = try await APIClient.shared.createProject(req)
                // 造物同样会落伴生散页，需连带刷新时间流
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
    /// 项目故事（设计手记）—— 修订时从原造物带出（MC-04）
    @State private var story: String
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
        _story = State(initialValue: project.story ?? "")
        _category = State(initialValue: project.category ?? "开源造物")
        // 存量英文/历史状态(Active 等)必须归一化为中文四态再进表单，
        // 否则未触碰状态直接保存会被后端白名单 400
        _status = State(initialValue: ProjectStatus.normalize(project.status).rawValue)
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
                // 项目类型是**选择**而非手填；已有值若不在字典中则补入，避免历史数据丢失
                PaperSelect(
                    selection: $category,
                    options: (appState.projectCategories.contains(category)
                               ? appState.projectCategories
                               : ([category] + appState.projectCategories)
                    ).map { PaperSelectOption(value: $0, label: $0) },
                    label: "项目类型："
                )
                // 关键（2026-10-25 修复）：状态只走下方快选胶囊，**删除手填框** ——
                // 同 NewProjectSheet：自由文本与快选同写字段，任意值会被展示层静默归一。
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

            // 项目故事：多行、纸质、斜体排印 —— 与「详细背景」区分开
            VStack(alignment: .leading, spacing: 4) {
                Text("项目故事")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("写下一段关于这个造物的故事…", text: $story, axis: .vertical)
                    .accessibilityLabel("项目故事")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.body))
                    .lineLimit(3...6)
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

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                Spacer()
                Button("保存项目修改") {
                    updateProject()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .paperButtonFocusRing()
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
                    // 关键（2026-10-25 修复）：subtitle / github_url 与 story 同口径**恒发** ——
                    // 原先 `isEmpty ? nil : …` 在删空时发 nil，后端更新是指针语义（省略=保持原值），
                    // 于是副标题与仓库链接从桌面端**永远清不掉**（保存成功提示但旧值复活）。
                    subtitle: subtitle,
                    description: description,
                    // 关键：修订时把故事**原样带回**，且**空串也要发**。
                    //
                    // 后端更新接口是指针语义（省略即保持原值）——
                    // 若桌面端不携带，用户在桌面端就永远看不到、也改不了这段故事
                    // （「用 Web 写故事、用桌面端改标题」之后桌面端就成了瞎子）；
                    // 但若写成 `story.isEmpty ? nil : story`，
                    // 用户把故事**删空**时发的就是 nil ⇒ 服务端保持原值 ⇒ **永远清不掉**。
                    // 所以这里始终携带：空串即「清空」。
                    story: story,
                    category: category.isEmpty ? nil : category,
                    status: status.isEmpty ? nil : status,
                    githubUrl: githubUrl,
                    // 展示顺序同样带回（后端省略即保持原值，这里显式带上以免被改序）
                    order: project.order
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
