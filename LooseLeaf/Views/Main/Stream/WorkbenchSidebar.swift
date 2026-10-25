import SwiftUI
import AppKit

/// 工作台左侧导航栏 (Workbench Sidebar)
/// 严格遵循 macOS HIG 与 macos-native-ui 规范：
/// 1. 采用 macOS 系统级 Vibrancy 半透明磨砂材质 (NSVisualEffectView sidebar) 融合温润纸张底色
/// 2. SF Symbols 全面升级为层次渲染 (hierarchical) 与 medium 缩放规范
/// 3. 精雕细琢的原生侧栏选中微胶囊、左侧朱砂指示线与指针悬停反馈
/// 4. 完美融合交通灯安全间隙与无感知窗口拖拽区域

struct WorkbenchSidebar: View {
    /// 底部状态文案：把「待同步 / 同步失败」的条数显性化，
    /// 否则用户只能靠猜为什么新内容没出现在中枢。
    private var statusLabel: String {
        var pending = 0
        var failed = 0
        for entry in appState.entries {
            switch entry.syncStatus ?? "synced" {
            case "pending_create": pending += 1
            case "failed": failed += 1
            default: break
            }
        }
        for tx in appState.transactions {
            switch tx.syncStatus ?? "synced" {
            case "pending_create": pending += 1
            case "failed": failed += 1
            default: break
            }
        }
        if failed > 0 { return "同步失败 \(failed) 条" }
        if pending > 0 { return "待同步 \(pending) 条" }
        if appState.isFlushingOutbox { return "同步中…" }
        return appState.isOnline ? "中枢就绪" : "离线发件箱守护"
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

            // 导航菜单项：6 大内容板块 + 5 个配置条目（扁平化后原「配置中心」tab 直接进侧栏）
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

                    // 系统配置组标题（可点击折叠/展开）
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isSystemGroupCollapsed.toggle()
                            UserDefaults.standard.set(isSystemGroupCollapsed, forKey: "looseleaf_ui_system_group_collapsed")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("系统配置")
                            Image(systemName: isSystemGroupCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 7.5, weight: .semibold))
                        }
                        .font(ArchiveTypography.monoScale(size: 9.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSystemGroupCollapsed ? "展开系统配置分组" : "折叠系统配置分组")

                    if !isSystemGroupCollapsed {
                        ForEach(WorkbenchSection.configurationSections) { section in
                            WorkbenchNavRow(
                                section: section,
                                selected: appState.activeSection == section
                            ) {
                                guard appState.activeSection != section else { return }
                                onSelect(section)
                            }
                        }
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
                        .fill(appState.isOnline ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .frame(width: 5.5, height: 5.5)

                    Text(statusLabel)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .accessibilityLabel(statusLabel)

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
                        .help("把所有待同步 / 同步失败的内容重新上传到中枢")
                        .accessibilityLabel("重新上传全部待同步内容")
                    }

                    Spacer()

                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text("⇧⌘L")
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
                    .help("呼出极速闪念与记账悬浮面板 (⇧⌘L)")
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
        let action: () -> Void

        @State private var isHovering: Bool = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: section.icon)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(selected ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                        .frame(width: 18)

                    Text(section.title)
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
