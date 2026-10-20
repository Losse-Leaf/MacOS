import SwiftUI

/// macOS 标题栏窗口拖拽手势区域（配合 .hiddenTitleBar 实现全区域平滑拖拽）
/// 板块画布最大阅读行宽：宽屏下内容居中陈列，两侧自然呈现宣纸留白
struct WorkbenchCanvasMaxWidth: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}
