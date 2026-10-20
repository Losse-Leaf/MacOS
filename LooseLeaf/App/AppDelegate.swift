import AppKit
import SwiftUI
import Carbon
import CoreSpotlight
@preconcurrency import UserNotifications
import os

/// 应用系统事件与全局快捷键托管代理 (AppDelegate)
/// 严格遵循 docs/macos.md §3.1 规范：
/// 1. 注册系统级全局快捷键 Cmd + Shift + L (Carbon RegisterEventHotKey，无需额外辅助功能权限即可跨应用静默呼出)
/// 2. 托管轻量级悬浮捕捉面板 (NSPanel)，支持 ESC 或失去焦点自动收起
/// 3. 响应 looseleaf:// 自定义协议配对
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static let hotKeyCodeKey = "looseleaf_hotkey_keycode"
    public static let hotKeyModifiersKey = "looseleaf_hotkey_modifiers"

    private static let logger = Logger(subsystem: "com.looseleaf.mac", category: "app")

    private var quickCapturePanel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 图标策略（用户可关闭，让应用只驻留菜单栏）
        let showsDockIcon = UserDefaults.standard.object(forKey: "looseleaf_shows_dock_icon") as? Bool ?? true
        NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
        if showsDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.servicesProvider = self
        registerGlobalHotKeyFromPreferences()

        // 窗口状态记忆：让系统自动保存主窗口的位置与尺寸
        restoreMainWindowFrame()

        // 主窗口不再开启背景拖拽：内容区点选 / 文本选择 / 热力图交互易误拖窗口，
        // 仅保留 QuickCapturePanel 浮动小窗的背景拖拽（在其构造处单独设置）。

        // 清理历史遗留的暗房拖拽临时文件
        DropLoader.cleanupStaleDropFiles()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // 防抖窗口内的最后一次修改必须落盘
        SyncManager.shared.flushSnapshotToDiskIfNeeded()
        // Spotlight 索引有 1.5 秒防抖，退出前必须立即提交，否则最近变更的条目搜不到
        SpotlightIndexer.flushNow()
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

    public func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        if userActivity.activityType == CSSearchableItemActionType,
           let uniqueId = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            if uniqueId.hasPrefix("looseleaf-entry-"),
               let idStr = uniqueId.split(separator: "-").last,
               let entryId = Int(idStr) {
                AppState.shared.navigateToEntry(id: entryId)
                return true
            }
        }
        return false
    }

    /// 恢复主窗口尺寸与位置（macOS 的 frame autosave）
    private func restoreMainWindowFrame() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })
                ?? NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
            let autosaveName = "LooseLeafMainWindow"
            if !window.setFrameUsingName(autosaveName) {
                // 首次启动没有保存记录：用默认尺寸居中
                window.center()
            }
            window.setFrameAutosaveName(autosaveName)
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // 优先唤回主工作台窗口，避免把浮动捕捉面板当成主窗口
            let mainWindow = sender.windows.first { $0.identifier?.rawValue == "main" }
                ?? sender.windows.first { $0.canBecomeMain }
            mainWindow?.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }

    // MARK: - 系统通知 (User Notifications)

    /// 发送一条本地系统通知（同步完成 / 失败 / 备份完成等关键事件）
    @MainActor
    public static func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 请求通知授权（仅在用户开启相关偏好后调用一次）
    @MainActor
    public static func requestNotificationAuthorizationIfNeeded() {
        // 使用异步 API：UNUserNotificationCenter 未标注 Sendable，
        // 在主线程上就地调用可避免把非 Sendable 实例捕获进 @Sendable 闭包。
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
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
            panel.onResignKey = { [weak self] in
                self?.closeQuickCapturePanel()
            }
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
    }

    public func closeQuickCapturePanel() {
        quickCapturePanel?.orderOut(nil)
    }
}

/// 允许无边框浮动面板接收键盘焦点与输入，支持失焦与 ESC 自动收起
private final class KeyableFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onResignKey: (() -> Void)?

    override func resignKey() {
        super.resignKey()
        // 延迟短暂检测，避免系统 DatePicker 弹层、下拉菜单或文件选择弹窗短暂抢焦点导致面板误收起
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            guard !self.isKeyWindow else { return }
            if let keyWin = NSApp.keyWindow, keyWin !== self {
                // 只依赖**公开 API** 判断子窗口/附属窗口关系；
                // 原先通过 className.contains("Popover") 之类的私有类名判断，
                // 系统升级改名即失效，且 NSApp.modalWindow != nil 过于宽松。
                let isOwned = self.childWindows?.contains(where: { $0 === keyWin }) == true
                    || keyWin.sheetParent === self
                    || keyWin.parent === self
                if isOwned {
                    return
                }
                // 本面板自己的弹出层（Popover / DatePicker）其 parent 就是本面板，
                // 已被上面的 isOwned 覆盖；系统模态窗口（文件选择框等）打开期间也不应收起。
                if NSApp.modalWindow != nil {
                    return
                }
            }
            self.onResignKey?()
        }
    }

    // 说明：原先在此覆写 cancelOperation 处理 ESC 收起，与 SwiftUI 视图层的
    // `.onExitCommand` 形成双重处理（ESC 可能被消费两次）。
    // 现统一由视图层负责 ESC，此处不再拦截。
}
