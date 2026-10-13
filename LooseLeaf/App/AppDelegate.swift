import AppKit
import SwiftUI
import Carbon
import os

/// 应用系统事件与全局快捷键托管代理 (AppDelegate)
/// 严格遵循 docs/macos.md §3.1 规范：
/// 1. 注册系统级全局快捷键 Cmd + Shift + L (Carbon RegisterEventHotKey，无需额外辅助功能权限即可跨应用静默呼出)
/// 2. 托管轻量级悬浮捕捉面板 (NSPanel)，支持 ESC 或失去焦点自动收起
/// 3. 响应 looseleaf:// 自定义协议配对与小组件深链跳转
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static let hotKeyCodeKey = "looseleaf_hotkey_keycode"
    public static let hotKeyModifiersKey = "looseleaf_hotkey_modifiers"

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "app")

    private var quickCapturePanel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.servicesProvider = self
        registerGlobalHotKeyFromPreferences()
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

    // MARK: - 系统服务菜单：摘录选中文本到散页

    /// 系统右键「服务」菜单入口（Info.plist NSServices 注册，NSPortName = LooseLeaf）
    @objc public func captureTextFromService(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            error.pointee = "选中内容不含文本" as NSString
            return
        }
        AppState.shared.pendingCaptureText = text
        showQuickCapturePanel()
    }

    // MARK: - 全局热键注册、自定义与显示

    /// 全局热键显示名（由当前键位与修饰键动态生成，如 "⌘ + ⇧ + L"）
    public static var hotKeyDisplayName: String {
        let code = UserDefaults.standard.object(forKey: hotKeyCodeKey) as? Int ?? Int(kVK_ANSI_L)
        let mods = UserDefaults.standard.object(forKey: hotKeyModifiersKey) as? Int ?? Int(cmdKey | shiftKey)
        return displayString(keyCode: code, carbonModifiers: mods)
    }

    /// 将 Carbon 键位 + 修饰键转换为人类可读串（⌃⌥⇧⌘ 顺序，macOS 惯例）
    public static func displayString(keyCode: Int, carbonModifiers: Int) -> String {
        var parts: [String] = []
        if carbonModifiers & Int(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & Int(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & Int(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & Int(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeNames[keyCode] ?? "Key(\(keyCode))")
        return parts.joined(separator: " + ")
    }

    private static let keyCodeNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥", kVK_Delete: "⌫"
    ]

    private func registerGlobalHotKeyFromPreferences() {
        let code = UserDefaults.standard.object(forKey: Self.hotKeyCodeKey) as? Int ?? Int(kVK_ANSI_L)
        let mods = UserDefaults.standard.object(forKey: Self.hotKeyModifiersKey) as? Int ?? Int(cmdKey | shiftKey)
        registerGlobalHotKey(keyCode: code, modifiers: mods)
    }

    /// 应用新的全局热键（注销旧注册、持久化偏好并立即生效）
    public func applyHotKey(keyCode: Int, carbonModifiers: Int) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        UserDefaults.standard.set(keyCode, forKey: Self.hotKeyCodeKey)
        UserDefaults.standard.set(carbonModifiers, forKey: Self.hotKeyModifiersKey)
        registerGlobalHotKey(keyCode: keyCode, modifiers: carbonModifiers)
    }

    private func registerGlobalHotKey(keyCode: Int, modifiers: Int) {
        if eventHandlerRef == nil {
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
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4C4152), id: 1) // 'LLAR'
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            let display = Self.displayString(keyCode: keyCode, carbonModifiers: modifiers)
            Self.logger.info("Global hotkey registered: \(display, privacy: .public)")
        } else {
            Self.logger.error("Global hotkey registration failed, status: \(status)")
        }
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
        // 面板出现在鼠标所在的屏幕（多显示器友好），回退到主屏
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen = targetScreen {
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
