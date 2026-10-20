import SwiftUI
import AppKit

/// AppKit 桥接控件集合 (AppKit Bridges)
/// 集中存放所有 `NSViewRepresentable` 桥接，避免把 AppKit 细节散落在业务视图里。

/// 窗口拖拽把手：仅标题栏区域可拖动窗口，
/// 避免内容区的点击选择 / 热力图交互被误判为拖动窗口。
public struct WindowDragHandleView: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    public func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

/// 可拖动窗口的空白 NSView
public final class WindowDragNSView: NSView {
    public override var mouseDownCanMoveWindow: Bool { true }
}
