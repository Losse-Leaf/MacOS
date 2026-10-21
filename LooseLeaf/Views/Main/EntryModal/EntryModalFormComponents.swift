// EntryModalFormComponents.swift
// 创作模态表单纸本输入控件
// 职责：抽出五个表单子 View 共用的纸本输入框，样式与原 NewEntryModal 内联写法完全一致。

import SwiftUI

/// 纸本单行输入框
///
/// 样式与原 `NewEntryModal` 中的内联写法逐项对齐（纯文本样式 + 纸色底 + 圆角裁切）。
struct EntryPaperField: View {
    let placeholder: String
    @Binding var text: String
    var font: Font
    var padding: CGFloat = 10
    var background: Color = ArchivePalette.archiveSubtle
    var cornerRadius: CGFloat = 6

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .padding(padding)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// 纸本多行输入框（纵向自适应高度）
///
/// 样式与原 `NewEntryModal` 中的内联写法逐项对齐。
struct EntryPaperTextArea: View {
    let placeholder: String
    @Binding var text: String
    var font: Font
    var padding: CGFloat = 10
    var lineLimit: ClosedRange<Int>

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(font)
            .lineLimit(lineLimit)
            .padding(padding)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
