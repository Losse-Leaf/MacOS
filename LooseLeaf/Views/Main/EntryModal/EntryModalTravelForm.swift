// EntryModalTravelForm.swift
// 创作模态 · 游历形态表单
// 职责：独立子 View，只订阅草稿中与「游历」相关的字段，未选中时根本不会挂载。

import SwiftUI

/// 游历形态表单（行迹 / 漫游记忆）
struct EntryModalTravelForm: View {
    @Bindable var draft: EntryDraft
    let appState: AppState
    let media: EntryMediaState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PaperCityPicker(selectedCode: $draft.cityCode, selectedName: $draft.cityName)

                if !appState.footprints.isEmpty {
                    let fpOptions: [PaperSelectOption<Int?>] = [PaperSelectOption(value: nil, label: "新建独立漫游")] + appState.footprints.map { fp in
                        PaperSelectOption(value: fp.id, label: "\(fp.cityName) · \(fp.title ?? "行旅")")
                    }
                    PaperSelect(selection: $draft.selectedFootprintId, options: fpOptions, label: "关联足迹")
                }
            }

            HStack(spacing: 12) {
                PaperDatePicker(selection: $draft.occurredAt, enableTime: true, label: "启程/抵达时刻")
                PaperDatePicker(selection: $draft.departedAt, enableTime: true, label: "离开时刻")
            }

            EntryPaperField(
                placeholder: "旅途标题（例：西湖暮色寻茶记）",
                text: $draft.title,
                font: ArchiveTypography.editorialSerif(size: 15, weight: .medium)
            )

            EntryPaperTextArea(
                placeholder: "记下旅途行迹、见闻感受与山川光影…",
                text: $draft.content,
                font: ArchiveTypography.bodySans(size: 13),
                lineLimit: 5...10
            )

            EntryMediaAttachmentsSection(media: media)
        }
    }
}
