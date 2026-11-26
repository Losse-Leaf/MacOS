import SwiftUI
import AppKit

/// 工作台左侧导航栏 (Workbench Sidebar)
/// 遵循 macOS HIG 规范：
/// 1. 导航列表采用原生 `List(selection:)` + `.listStyle(.sidebar)`，交还系统键盘导航、焦点环与选中态语义
/// 2. `.scrollContentBackground(.hidden)` 叠加 `WindowVibrancyView` 与暖纸薄层，在壳层原生与纸感之间保持克制平衡
/// 3. 「偏好与设置…」与极速捕捉热键置于底栏工具区，确保导航选择态语义纯净
struct WorkbenchSidebar: View {
    @Bindable var appState: AppState
    var onSelect: (WorkbenchSection) -> Void

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var badgeState: HubConnectionBadgeState {
        appState.hubConnectionBadgeState
    }

    private var sectionSelectionBinding: Binding<WorkbenchSection?> {
        Binding(
            get: {
                WorkbenchSection.contentSections.contains(appState.activeSection)
                    ? appState.activeSection
                    : .stream
            },
            set: { newValue in
                guard let newValue, newValue != appState.activeSection else { return }
                onSelect(newValue)
            }
        )
    }

    private func pendingBadgeCount(for section: WorkbenchSection) -> Int {
        switch section {
        case .stream: return appState.entriesNeedingUpload
        case .ledger: return appState.transactionsNeedingUpload
        case .preferences, .hub, .about: return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 刊头印记 (100% 动态读取后端配置与主理人档案)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: "leaf.fill")
                        .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.heading, weight: .medium))
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ArchivePalette.accentMoss)
                        .accessibilityHidden(true)

                    Text(appState.siteConfig.siteName.isEmpty ? "散页 · 时光手账" : appState.siteConfig.siteName)
                        .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                }

                if !appState.profile.name.isEmpty || !appState.profile.displayCity.isEmpty {
                    Text(
                        [appState.profile.name, appState.profile.displayCity]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                    )
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.label))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 原生侧栏列表（散页 / 记账）
            List(selection: sectionSelectionBinding) {
                Section("生活卷宗") {
                    ForEach(WorkbenchSection.contentSections) { section in
                        Label(section.title, systemImage: section.icon)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading))
                            .imageScale(.medium)
                            .tag(section)
                            .badge(pendingBadgeCount(for: section))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            // 底部工具与系统状态区（偏好与设置 + 中枢连接态 + 极速捕捉热键）
            VStack(alignment: .leading, spacing: 6) {
                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))

                Button {
                    appState.navigation.settingsSelectedTab = .general
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: ArchiveIcon.preferences.systemName)
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.body, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text("偏好与设置…")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                        Spacer(minLength: 4)
                        Text("⌘,")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                .help("打开活页集偏好设置 (⌘,)")

                HStack(spacing: 5) {
                    if differentiateWithoutColor {
                        Image(systemName: badgeState.symbolName)
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.micro, weight: .medium))
                            .foregroundStyle(badgeState.dotColor)
                            .accessibilityHidden(true)
                    } else {
                        Circle()
                            .fill(badgeState.dotColor)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }

                    Text(badgeState.label)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if appState.entriesNeedingUpload + appState.transactionsNeedingUpload > 0 {
                        Button {
                            appState.reuploadAllPending()
                        } label: {
                            Text("全部重传")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro, weight: .semibold))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .underline()
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: 3)
                        .help("把所有待同步 / 同步失败的内容重新上传到中枢")
                        .accessibilityLabel("重新上传全部待同步内容")
                    }
                }

                Button {
                    (NSApp.delegate as? AppDelegate)?.toggleQuickCapturePanel()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.miniBadge))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .accessibilityHidden(true)
                        Text("极速闪念")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(AppDelegate.hotKeyDisplayName)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.badge, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(ArchivePalette.archivePaper.opacity(reduceTransparency ? 1.0 : 0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: 3)
                .help("呼出极速闪念与记账悬浮面板 (\(AppDelegate.hotKeyDisplayName))")
                .accessibilityLabel("呼出极速闪念与记账悬浮面板，快捷键 \(AppDelegate.hotKeyDisplayName)")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background {
            if reduceTransparency {
                ArchivePalette.archiveSubtle
            } else {
                ZStack {
                    WindowVibrancyView(material: .sidebar, blendingMode: .behindWindow)
                    ArchivePalette.archivePaper.opacity(0.78)
                }
            }
        }
    }
}
