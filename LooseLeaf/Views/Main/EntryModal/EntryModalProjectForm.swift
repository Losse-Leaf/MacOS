// EntryModalProjectForm.swift
// 创作模态 · 造物形态表单
// 职责：独立子 View，只订阅草稿中与「造物」相关的字段，未选中时根本不会挂载。

import SwiftUI

/// 造物形态表单（立项新造物 / 追加进展手记）
struct EntryModalProjectForm: View {
    @Bindable var draft: EntryDraft
    let appState: AppState
    let media: EntryMediaState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSegmentedControl(
                selection: $draft.projectMode,
                items: [
                    PaperSegmentItem("entry", title: "追加进展手记", icon: "pencil.line"),
                    PaperSegmentItem("new", title: "立项新造物", icon: "plus.circle")
                ]
            )

            if draft.projectMode == "new" {
                EntryPaperField(
                    placeholder: "造物项目名称（例：Loose-Leaf macOS 客户端）",
                    text: $draft.newProjectTitle,
                    font: ArchiveTypography.editorialSerif(size: 15, weight: .medium)
                )

                HStack(spacing: 12) {
                    let catOptions = appState.projectCategories.map { PaperSelectOption(value: $0, label: $0) }
                    PaperSelect(selection: $draft.newProjectCategory, options: catOptions, label: "项目类别")

                    let statusOptions = [
                        PaperSelectOption(value: "Active", label: "进行中 (Active)"),
                        PaperSelectOption(value: "Archived", label: "已完结 (Archived)")
                    ]
                    PaperSelect(selection: $draft.newProjectStatus, options: statusOptions, label: "当前状态")
                }

                EntryPaperField(
                    placeholder: "一句话副标（例：轻量原生架构）",
                    text: $draft.newProjectSubtitle,
                    font: ArchiveTypography.bodySans(size: 12.5),
                    padding: 8
                )

                EntryPaperField(
                    placeholder: "代码仓或产品直链（GitHub / URL）",
                    text: $draft.newProjectGithub,
                    font: ArchiveTypography.monoScale(size: 11.5),
                    padding: 8
                )

                EntryPaperTextArea(
                    placeholder: "项目简介与核心设计思想…",
                    text: $draft.newProjectDesc,
                    font: ArchiveTypography.bodySans(size: 12.5),
                    padding: 8,
                    lineLimit: 3...6
                )
            } else {
                if appState.projects.isEmpty {
                    Text("当前尚无进行中的造物项目，请切换至「立项新造物」完成初始立项。")
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkMuted)
                } else {
                    let projOptions: [PaperSelectOption<Int?>] = appState.projects.map { proj in
                        PaperSelectOption(value: proj.id as Int?, label: proj.title, sublabel: proj.category ?? "未分类")
                    }
                    PaperSelect(selection: $draft.selectedProjectId, options: projOptions, placeholder: "选择归属造物项目…", label: "归属造物")

                    EntryPaperField(
                        placeholder: "手记主题（例：完成 1:1 架构对齐）",
                        text: $draft.title,
                        font: ArchiveTypography.editorialSerif(size: 14.5, weight: .medium)
                    )

                    EntryPaperTextArea(
                        placeholder: "记录造物阶段性进展与攻坚思考…",
                        text: $draft.content,
                        font: ArchiveTypography.bodySans(size: 13),
                        lineLimit: 5...10
                    )

                    HStack(spacing: 12) {
                        PaperDatePicker(selection: $draft.occurredAt, enableTime: true, label: "进展时刻")
                        PaperCityPicker(selectedCode: $draft.cityCode, selectedName: $draft.cityName)
                    }

                    EntryMediaAttachmentsSection(media: media)
                }
            }
        }
    }
}
