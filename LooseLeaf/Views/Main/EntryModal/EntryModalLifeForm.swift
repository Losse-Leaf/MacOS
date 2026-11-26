// EntryModalLifeForm.swift
// 创作模态 · 日常形态表单
// 职责：独立子 View，只订阅草稿中与「日常」相关的字段，未选中时根本不会挂载。

import SwiftUI

/// 日常形态表单（散页 / 随笔）
///
/// **设计：朋友圈式单输入框 + 原生内容分类**
/// 不再单列「标题」输入框 —— 就像发朋友圈一样，只写正文，
/// 标题由**正文第一行**自动派生（`FormatUtils.derivedTitle`），
/// 用于列表展示、全局检索与 Spotlight 索引。
/// 想显式给标题时，仍可在编辑已建成的散页时补上。
///
/// **性能要点**：本 View 独立成体，输入正文时只会重绘本视图，
/// 父 `NewEntryModal` 的 body 不受影响。
struct EntryModalLifeForm: View {
    @Bindable var draft: EntryDraft
    let media: EntryMediaState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EntryCategoryPickerRow(selection: $draft.category, label: "分类：", isCompact: false)

            // 朋友圈式：一个大正文框，标题由第一行派生
            EntryPaperTextArea(
                placeholder: "此刻在想什么…",
                text: $draft.content,
                font: ArchiveTypography.bodySans(size: ArchiveTypography.Scale.subheadline),
                lineLimit: 6...16
            )

            // 派生出的标题预览（让人知道标题是怎么来的，也方便反悔改写；恒驻单行杜绝打字瞬间 26pt 跳变）
            let hasContent = !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            HStack(spacing: 6) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.badge))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .accessibilityHidden(true)
                Text(hasContent ? "标题将取正文首行：\(FormatUtils.derivedTitle(from: draft.content))" : "标题将自动取正文首行")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("标题将自动取正文首行")

            let timeBinding = Binding<Date>(
                get: { draft.occurredAt },
                set: {
                    draft.occurredAt = $0
                    draft.userEditedTime = true
                }
            )
            let locationBinding = Binding<String>(
                get: { draft.location },
                set: {
                    draft.location = $0
                    draft.userEditedLocation = !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            )
            HStack(spacing: 12) {
                PaperDatePicker(selection: timeBinding, enableTime: true, label: "发生时刻")
                TextField("地点（可选）", text: locationBinding)
                    .accessibilityLabel("地点")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                    )
            }

            EntryMediaAttachmentsSection(media: media)
        }
    }
}
