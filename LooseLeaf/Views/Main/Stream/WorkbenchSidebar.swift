import SwiftUI
import AppKit

/// 工作台左侧导航栏 (Workbench Sidebar)
/// 严格遵循 macOS HIG 与 macos-native-ui 规范：
/// 1. 采用 macOS 系统级 Vibrancy 半透明磨砂材质 (NSVisualEffectView sidebar) 融合温润纸张底色
/// 2. SF Symbols 全面升级为层次渲染 (hierarchical) 与 medium 缩放规范
/// 3. 精雕细琢的原生侧栏选中微胶囊、左侧朱砂指示线与指针悬停反馈
/// 4. 完美融合交通灯安全间隙与无感知窗口拖拽区域

struct WorkbenchSidebar: View {
    private var badgeState: HubConnectionBadgeState {
        appState.hubConnectionBadgeState
    }

    @Bindable var appState: AppState
    @Binding var isSystemGroupCollapsed: Bool
    /// 选中板块的回调（由主视图统一处理状态同步）
    var onSelect: (WorkbenchSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 刊头印记 (100% 动态读取后端配置与主理人档案)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 13, weight: .medium))
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ArchivePalette.accentMoss)

                    Text(appState.siteConfig.siteName.isEmpty ? "散页 · 时光手账" : appState.siteConfig.siteName)
                        .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .lineLimit(1)
                }

                if !appState.profile.name.isEmpty || !appState.profile.displayCity.isEmpty {
                    Text(
                        [appState.profile.name, appState.profile.displayCity]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                    )
                    .font(ArchiveTypography.monoScale(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 42)
            .overlay(
                WindowDragHandleView()
                    .frame(height: 48),
                alignment: .top
            )

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 导航菜单项：6 大内容板块 + 统一系统设置入口
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("生活卷宗")
                        .font(ArchiveTypography.monoScale(size: 9.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                        .padding(.bottom, 3)

                    ForEach(WorkbenchSection.contentSections) { section in
                        WorkbenchNavRow(
                            section: section,
                            selected: appState.activeSection == section
                        ) {
                            guard appState.activeSection != section else { return }
                            onSelect(section)
                        }
                    }

                    Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                        .padding(.vertical, 6)

                    // 统一系统设置入口（对齐 macOS HIG）
                    WorkbenchNavRow(
                        section: .preferences,
                        selected: WorkbenchSection.configurationSections.contains(appState.activeSection),
                        customTitle: "偏好与设置",
                        customIcon: "gearshape"
                    ) {
                        guard !WorkbenchSection.configurationSections.contains(appState.activeSection) else { return }
                        onSelect(.preferences)
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 8)

            // 底部仅保留系统状态（配置入口已全部进侧栏）
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))

                // 中枢就绪状态与快捷记账提示
                HStack(spacing: 5) {
                    Circle()
                        .fill(badgeState.dotColor)
                        .frame(width: 5.5, height: 5.5)

                    Text(badgeState.label)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .accessibilityLabel(badgeState.label)

                    if appState.entriesNeedingUpload + appState.transactionsNeedingUpload > 0 {
                        Button {
                            appState.reuploadAllPending()
                        } label: {
                            Text("重传")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro, weight: .semibold))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: 3)
                        .help("把所有待同步 / 同步失败的内容重新上传到中枢")
                        .accessibilityLabel("重新上传全部待同步内容")
                    }

                    Spacer()

                    Button {
                        (NSApp.delegate as? AppDelegate)?.toggleQuickCapturePanel()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(ArchivePalette.accentWarm)
                            Text(AppDelegate.hotKeyDisplayName)
                                .font(ArchiveTypography.monoScale(size: 9.5, weight: .medium))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(ArchivePalette.archivePaper.opacity(0.85))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .paperButtonFocusRing(cornerRadius: 3)
                    .help("呼出极速闪念与记账悬浮面板 (\(AppDelegate.hotKeyDisplayName))")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background {
            ZStack {
                WindowVibrancyView(material: .sidebar, blendingMode: .behindWindow)
                ArchivePalette.archivePaper.opacity(0.78)
            }
        }
    }

    /// 侧边导航行：符合 macOS HIG 规范，支持层级 SF Symbols、微胶囊背景与左侧朱砂指示线
    struct WorkbenchNavRow: View {
        let section: WorkbenchSection
        let selected: Bool
        var customTitle: String? = nil
        var customIcon: String? = nil
        let action: () -> Void

        @State private var isHovering: Bool = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: customIcon ?? section.icon)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(selected ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                        .frame(width: 18)

                    Text(customTitle ?? section.title)
                        .font(ArchiveTypography.bodySans(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? ArchivePalette.inkPrimary : ArchivePalette.inkSecondary)

                    Spacer()
                }
                .padding(.leading, 10)
                .padding(.trailing, 10)
                .padding(.vertical, 6.5)
                .background(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .fill(rowFill)
                )
                .overlay(alignment: .leading) {
                    if selected {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(ArchivePalette.accentWarm)
                            .frame(width: 2.5, height: 14)
                            .padding(.leading, 2)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .stroke(selected ? ArchivePalette.borderDivider.opacity(0.6) : Color.clear, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .paperButtonFocusRing(cornerRadius: ArchiveRadius.sm)
            .animation(.easeOut(duration: 0.14), value: selected)
            .animation(.easeOut(duration: 0.1), value: isHovering)
            .onHover { isHovering = $0 }
            .accessibilityLabel(section.title)
            .accessibilityValue(selected ? "已选中" : "未选中")
            .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
        }

        private var rowFill: Color {
            if selected { return ArchivePalette.archiveSubtle }
            return isHovering ? ArchivePalette.archiveSubtle.opacity(0.55) : .clear
        }
    }
}
