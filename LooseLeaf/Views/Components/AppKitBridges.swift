import SwiftUI
import AppKit

/// AppKit 桥接控件集合 (AppKit Bridges)
/// 集中存放所有 `NSViewRepresentable` 与系统窗口/按键桥接，避免把 AppKit 细节散落在业务视图里。

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

/// 监听宿主 NSWindow 关闭事件（如主窗口退驻菜单栏时主动释放图片解码内存池）
public struct HostingWindowCloseObserver: NSViewRepresentable {
    public var onWindowWillClose: @MainActor () -> Void

    public init(onWindowWillClose: @escaping @MainActor () -> Void) {
        self.onWindowWillClose = onWindowWillClose
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onWindowWillClose: onWindowWillClose)
    }

    public func makeNSView(context: Context) -> WindowObserverNSView {
        let view = WindowObserverNSView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.observe(window: window)
        }
        return view
    }

    public func updateNSView(_ nsView: WindowObserverNSView, context: Context) {
        context.coordinator.onWindowWillClose = onWindowWillClose
    }

    public final class WindowObserverNSView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }

    @MainActor
    public final class Coordinator {
        var onWindowWillClose: @MainActor () -> Void
        private weak var observedWindow: NSWindow?
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        init(onWindowWillClose: @escaping @MainActor () -> Void) {
            self.onWindowWillClose = onWindowWillClose
        }

        func observe(window: NSWindow?) {
            guard observedWindow !== window else { return }
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            observedWindow = window
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.onWindowWillClose()
                }
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

/// 局部 `⌘V` 剪贴板截图拦截修饰符：
/// 当输入框（`NSTextView` field editor）聚焦时，SwiftUI 的 `.onPasteCommand` 会被系统文本粘贴吞掉。
/// 此监视器仅在「当前窗口为 keyWindow，且剪贴板含图片/图片文件且不含普通纯文本」时拦截 `⌘V` 走相纸冲印；
/// 若剪贴板含文本则原样放行给 `NSTextView` 执行原生文本粘贴。
private struct PasteboardImageShortcutModifier: ViewModifier {
    let onPasteImage: @MainActor () -> Void
    @State private var monitor: Any?
    @State private var hostWindowBox = WeakWindowBox()

    final class WeakWindowBox: @unchecked Sendable {
        weak var window: NSWindow?
    }

    func body(content: Content) -> some View {
        content
            .background(
                WindowCaptureProbe { win in
                    hostWindowBox.window = win
                }
            )
            .onAppear {
                guard monitor == nil else { return }
                let box = hostWindowBox
                let action = onPasteImage
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    guard flags == .command,
                          event.charactersIgnoringModifiers?.lowercased() == "v" else {
                        return event
                    }
                    if let targetWin = box.window, NSApp.keyWindow !== targetWin {
                        return event
                    }
                    let pb = NSPasteboard.general
                    if Self.pasteboardHasImageOnly(pb) {
                        Task { @MainActor in
                            action()
                        }
                        return nil
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
    }

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp", "dng", "arw", "cr2", "cr3", "nef", "raf"
    ]

    private static func pasteboardHasImageOnly(_ pb: NSPasteboard) -> Bool {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           urls.contains(where: { imageExtensions.contains($0.pathExtension.lowercased()) }) {
            return true
        }
        let plainText = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard plainText.isEmpty else {
            return false
        }
        return pb.data(forType: .png) != nil
            || pb.data(forType: .tiff) != nil
            || NSImage.canInit(with: pb)
    }
}

private struct WindowCaptureProbe: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void
    func makeNSView(context: Context) -> ProbeNSView {
        let v = ProbeNSView()
        v.onResolve = onResolve
        return v
    }
    func updateNSView(_ nsView: ProbeNSView, context: Context) {
        nsView.onResolve = onResolve
    }
    final class ProbeNSView: NSView {
        var onResolve: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onResolve?(window)
        }
    }
}

public extension View {
    /// 支持在聚焦文本输入框内按 `⌘V` 直接粘贴剪贴板截图/照片文件（含普通文本时自动放行原生粘贴）
    func onPasteImageShortcut(perform action: @escaping @MainActor () -> Void) -> some View {
        modifier(PasteboardImageShortcutModifier(onPasteImage: action))
    }
}
