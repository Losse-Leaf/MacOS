// EntryModalLifeForm.swift
// 创作模态 · 日常形态表单
// 职责：独立子 View，只订阅草稿中与「日常」相关的字段，未选中时根本不会挂载。

import SwiftUI

/// 日常形态表单（散页 / 随笔）
///
/// **性能要点**：本 View 独立成体，输入标题或正文时只会重绘本视图，
/// 父 `NewEntryModal` 的 body 与其它四个分支完全不受影响。
struct EntryModalLifeForm: View {
    @Bindable var draft: EntryDraft
    let media: EntryMediaState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EntryPaperField(
                placeholder: "标题（可选，留白则以正文第一行呈现）",
                text: $draft.title,
                font: ArchiveTypography.editorialSerif(size: 15, weight: .medium)
            )

            EntryPaperTextArea(
                placeholder: "记下这一刻的思绪、见闻或生活琐记…",
                text: $draft.content,
                font: ArchiveTypography.bodySans(size: 13),
                lineLimit: 5...10
            )

            HStack(spacing: 12) {
                PaperDatePicker(selection: $draft.occurredAt, enableTime: true, label: "发生时刻")
                PaperCityPicker(selectedCode: $draft.cityCode, selectedName: $draft.cityName)
                Toggle("精选散页", isOn: $draft.isFeatured)
                    .toggleStyle(.paperCheckbox)
                    .font(ArchiveTypography.bodySans(size: 11.5))
            }

            EntryMediaAttachmentsSection(media: media)
        }
    }
}
