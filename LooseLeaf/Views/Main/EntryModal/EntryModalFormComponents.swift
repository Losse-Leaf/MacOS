// EntryModalFormComponents.swift
// 创作模态表单纸本输入控件

import SwiftUI

/// 纸本单行输入框
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

/// 纸本多行输入框（纵向自适应伸展：从 `lowerBound` 初始高度平滑伸展至 `upperBound`）
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
            .frame(minHeight: CGFloat(lineLimit.lowerBound) * 19, alignment: .topLeading)
            .padding(padding)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
