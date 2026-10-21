// EntryModalLifeForm.swift
// 创作模态 · 日常形态表单
// 职责：独立子 View，只订阅草稿中与「日常」相关的字段，未选中时根本不会挂载。

import SwiftUI

/// 日常形态表单（散页 / 随笔）
///
/// **设计：朋友圈式单输入框**
/// 不再单列「标题」输入框 —— 就像发朋友圈一样，只写正文，
/// 标题由**正文第一行**自动派生（`FormatUtils.derivedTitle`），
/// 用于列表展示、全局检索与 Spotlight 索引。
/// 想显式给标题时，仍可在编辑已建成的散页时补上。
///
/// **性能要点**：本 View 独立成体，输入正文时只会重绘本视图，
/// 父 `NewEntryModal` 的 body 与其它四个分支完全不受影响。
struct EntryModalLifeForm: View {
    @Bindable var draft: EntryDraft
    let media: EntryMediaState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 朋友圈式：一个大正文框，标题由第一行派生
            EntryPaperTextArea(
                placeholder: "此刻在想什么…",
                text: $draft.content,
                font: ArchiveTypography.bodySans(size: 14),
                lineLimit: 6...16
            )

            // 派生出的标题预览（让人知道标题是怎么来的，也方便反悔改写）
            if !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 9.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .accessibilityHidden(true)
                    Text("标题将取正文首行：\(FormatUtils.derivedTitle(from: draft.content))")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("标题将自动取正文首行")
            }

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
