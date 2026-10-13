import AppKit
import SwiftUI
import Carbon

/// 应用系统事件与全局快捷键托管代理 (AppDelegate)
/// 严格遵循 docs/macos.md §3.1 规范：
/// 1. 注册系统级全局快捷键 Cmd + Shift + L (Carbon RegisterEventHotKey，无需额外辅助功能权限即可跨应用静默呼出)
/// 2. 托管轻量级悬浮捕捉面板 (NSPanel)，支持 ESC 或失去焦点自动收起
/// 3. 响应 looseleaf:// 自定义协议配对与小组件深链跳转
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var quickCapturePanel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        registerGlobalHotKey()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            AppState.shared.handleIncomingURL(url)
        }
    }

    // MARK: - 全局热键 Cmd + Shift + L 注册

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    delegate.toggleQuickCapturePanel()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4C4152), id: 1) // 'LLAR'
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_ANSI_L)

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    // MARK: - 极速闪念悬浮窗展开与收起

    public func toggleQuickCapturePanel() {
        if let panel = quickCapturePanel, panel.isVisible {
            closeQuickCapturePanel()
        } else {
            showQuickCapturePanel()
        }
    }

    public func showQuickCapturePanel() {
        if quickCapturePanel == nil {
            let panel = KeyableFloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let rootView = QuickCaptureView(appState: AppState.shared) { [weak self] in
                self?.closeQuickCapturePanel()
            }
            panel.contentView = NSHostingView(rootView: rootView)
            self.quickCapturePanel = panel
        }

        guard let panel = quickCapturePanel else { return }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 190
            let y = frame.maxY - 460
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AudioFeedback.shared.playPaperFlip()
    }

    public func closeQuickCapturePanel() {
        quickCapturePanel?.orderOut(nil)
    }
}

/// 允许无边框浮动面板接收键盘焦点与输入
private final class KeyableFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
