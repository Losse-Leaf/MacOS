import SwiftUI
import Carbon

/// 偏好设置（左侧菜单「偏好设置」入口）：纸本外观主题与全局快捷键录制
@MainActor
struct PreferencesSettingsView: View {
    @Bindable var appState: AppState

    // 全局热键录制状态
    @State private var hotKeyLabel: String = AppDelegate.hotKeyDisplayName
    @State private var isRecordingHotKey: Bool = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 20) {
            // 纸本外观主题
            settingsCardSection(title: "纸本外观主题", caption: "自适应色彩与排版") {
                HStack(spacing: 12) {
                    themeSwatchCard(
                        mode: .system,
                        title: "跟随系统",
                        subtitle: "随 macOS 自动切换浅色/暗色",
                        icon: "circle.lefthalf.filled"
                    )
                    themeSwatchCard(
                        mode: .paper,
                        title: "暖色棉纸",
                        subtitle: "天然棉纸米黄底色与炭黑墨迹",
                        icon: "sun.max.fill"
                    )
                    themeSwatchCard(
                        mode: .darkroom,
                        title: "暗房安全灯",
                        subtitle: "低照度琥珀暗调与微光纸本",
                        icon: "moon.fill"
                    )
                }
                .padding(12)
            }

            // 全局快捷键
            settingsCardSection(title: "全局快捷键", footer: "默认快捷键为 ⌥Space (Option + 空格)，在任意窗口下可唤起极速录入手账。") {
                settingsCardRow(
                    icon: "command",
                    iconColor: ArchivePalette.inkSecondary,
                    title: "全局呼出极速手账悬浮窗",
                    subtitle: "在任意应用程序窗口下随手唤起闪念录入与随行记账"
                ) {
                    HStack(spacing: 8) {
                        Text(hotKeyLabel)
                            .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(ArchivePalette.borderSubtle, lineWidth: 1))

                        if isRecordingHotKey {
                            Text("按下新组合键…")
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)

                            HotKeyRecorderView(isRecording: $isRecordingHotKey) { keyCode, modifiers in
                                (NSApp.delegate as? AppDelegate)?.applyHotKey(keyCode: keyCode, carbonModifiers: modifiers)
                                hotKeyLabel = AppDelegate.hotKeyDisplayName
                                isRecordingHotKey = false
                            }
                            .frame(width: 1, height: 1)
                            .opacity(0.01)
                        } else {
                            Button("修改按键") {
                                isRecordingHotKey = true
                            }
                            .font(ArchiveTypography.bodySans(size: 11))
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        }
                    }
                }
            }
        }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ArchivePalette.archivePaper)
    }
    private func themeSwatchCard(mode: AppearanceMode, title: String, subtitle: String, icon: String) -> some View {
        let isSelected = appState.appearanceMode == mode
        return Button {
            appState.appearanceMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(isSelected ? ArchivePalette.accentWarm.opacity(0.15) : ArchivePalette.borderSubtle.opacity(0.5))
                            .frame(width: 24, height: 24)
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSelected ? ArchivePalette.accentWarm : ArchivePalette.inkSecondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    } else {
                        Circle()
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 1)
                            .frame(width: 14, height: 14)
                    }
                }
                Text(title)
                    .font(ArchiveTypography.bodySans(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text(subtitle)
                    .font(ArchiveTypography.bodySans(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ArchivePalette.archivePaper : ArchivePalette.archiveSubtle.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle.opacity(0.7), lineWidth: isSelected ? 1.5 : 0.5)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.04) : Color.clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

// MARK: - 全局热键录制控件 (HotKeyRecorder)

struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCaptured: (Int, Int) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onCaptured = onCaptured
        view.onCancelled = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.onCaptured = onCaptured
        nsView.onCancelled = {
            isRecording = false
        }
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class RecorderNSView: NSView {
    var onCaptured: ((Int, Int) -> Void)?
    var onCancelled: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancelled?()
            return
        }
        var carbonModifiers: Int = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { carbonModifiers |= Int(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= Int(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= Int(shiftKey) }
        if flags.contains(.control) { carbonModifiers |= Int(controlKey) }
        guard carbonModifiers != 0 else { return }
        onCaptured?(Int(event.keyCode), carbonModifiers)
    }
}
}
