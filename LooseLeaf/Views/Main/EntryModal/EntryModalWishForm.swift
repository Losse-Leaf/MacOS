// EntryModalWishForm.swift
// 创作模态 · 心愿形态表单
// 职责：独立子 View，只订阅草稿中与「心愿」相关的字段，未选中时根本不会挂载。

import SwiftUI

/// 心愿形态表单（好物器物 / 行旅探索 / 阶段里程碑）
struct EntryModalWishForm: View {
    @Bindable var draft: EntryDraft
    let media: EntryMediaState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSegmentedControl(
                selection: $draft.wishKind,
                items: [
                    PaperSegmentItem("item", title: "好物器物", icon: "bag"),
                    PaperSegmentItem("travel", title: "行旅探索", icon: "airplane"),
                    PaperSegmentItem("milestone", title: "阶段里程碑", icon: "flag.checkered")
                ]
            )

            EntryPaperField(
                placeholder: draft.wishKind == "travel"
                    ? "旅程目的地或漫游愿景（例：京都秋日赏枫 / 环勃朗峰徒步）"
                    : (draft.wishKind == "milestone"
                        ? "里程碑名称（例：跑完人生第一场半马 / 独立发布首个产品）"
                        : "心愿好物名称（例：Leica M11 银色旁轴相机）"),
                text: $draft.title,
                font: ArchiveTypography.editorialSerif(size: 15, weight: .medium)
            )

            if draft.wishKind == "item" {
                EntryPaperField(
                    placeholder: "规格型号或意向（例：黑色银顶 / 35mm F1.4 / 国行现货）",
                    text: $draft.wishSpec,
                    font: ArchiveTypography.bodySans(size: 12.5),
                    padding: 8
                )
            } else if draft.wishKind == "travel" {
                PaperCityPicker(selectedCode: $draft.wishCityCode, selectedName: $draft.wishCityName, placeholder: "点选目的地省市…")
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("预估预算：¥")
                        .font(ArchiveTypography.monoScale(size: 12))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    TextField("0.00", text: $draft.wishBudgetYuan)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 13))
                }
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                PaperDatePicker(selection: $draft.wishTargetDate, label: "期望达成时期")
            }

            EntryPaperTextArea(
                placeholder: "为何心向往之？记下这份期冀背后的缘由、契机与初心…",
                text: $draft.content,
                font: ArchiveTypography.bodySans(size: 13),
                lineLimit: 4...7
            )

            EntryMediaAttachmentsSection(media: media)
        }
    }
}
