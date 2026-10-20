import SwiftUI

/// 工作台左侧导航栏 (Workbench Sidebar)
/// 从 StreamView 拆出：刊头印记、板块导航分组与中枢状态灯。
/// 选中板块后由外部回调统一处理，保持与主视图的状态同步。

struct WorkbenchSidebar: View {
    @Bindable var appState: AppState
        @Binding var isSystemGroupCollapsed: Bool
        /// 选中板块的回调（由主视图统一处理状态同步）
        var onSelect: (WorkbenchSection) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                // 刊头印记 (100% 动态读取后端配置与主理人档案)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 13))
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
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 44)
                .overlay(
                    WindowDragHandleView()
                        .frame(height: 38),
                    alignment: .top
                )

                Divider().overlay(ArchivePalette.borderSubtle)

                // 说明：原先此处有一个「⌘K 全局档案检索」按钮，与画布内的 ⌘F 搜索框
                // 视觉上高度相似，用户难以分辨两者关系；⌘K 已提升至原生窗口工具栏。

                // 导航菜单项：6 大内容板块 + 5 个配置条目（扁平化后原「配置中心」tab 直接进侧栏）
                // 12 行在 640pt 最小窗口高度下会贴边，故外层包 ScrollView 兜底
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("生活卷宗")
                            .font(ArchiveTypography.monoScale(size: 9.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 2)

                        ForEach(WorkbenchSection.contentSections) { section in
                            WorkbenchNavRow(
                                section: section,
                                selected: appState.activeSection == section
                            ) {
                                guard appState.activeSection != section else { return }
                                onSelect(section)
                            }
                        }

                        Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))
                            .padding(.vertical, 6)

                        // 系统配置组标题（可点击折叠/展开）
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isSystemGroupCollapsed.toggle()
                                UserDefaults.standard.set(isSystemGroupCollapsed, forKey: "looseleaf_ui_system_group_collapsed")
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text("系统配置")
                                Image(systemName: isSystemGroupCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 7, weight: .semibold))
                            }
                            .font(ArchiveTypography.monoScale(size: 9.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 2)
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

                // 辅助工具：银盐暗房不属于内容也不属于配置，单独收尾
                VStack(alignment: .leading, spacing: 4) {
                    Text("辅助工具")
                        .font(ArchiveTypography.monoScale(size: 9.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    WorkbenchNavRow(
                        section: .darkroom,
                        selected: appState.activeSection == .darkroom
                    ) {
                        guard appState.activeSection != .darkroom else { return }
                        onSelect(.darkroom)
                    }
                }
                .padding(.horizontal, 10)

                Spacer(minLength: 8)

                // 底部仅保留系统状态（配置入口已全部进侧栏）
                VStack(alignment: .leading, spacing: 8) {
                    Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))

                    // 中枢就绪状态与快捷记账提示
                    HStack(spacing: 5) {
                        Circle()
                            .fill(appState.isOnline ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                            .frame(width: 5, height: 5)
                        Text(appState.isOnline ? (appState.isFlushingOutbox ? "同步中…" : "中枢就绪") : "离线发件箱守护")
                            .font(ArchiveTypography.bodySans(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(ArchivePalette.accentWarm)
                            Text("快速记 ⇧⌘L")
                        }
                        .font(ArchiveTypography.monoScale(size: 9.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .background(ArchivePalette.archivePaper.opacity(0.65))
        }

        /// 侧边导航行：整行可点（contentShape 修透明背景不参与命中测试的问题），
        /// 悬停显背景、选中态 0.14s 局部过渡——反馈即时且动画不外溢全树。

        struct WorkbenchNavRow: View {
            let section: WorkbenchSection
            let selected: Bool
            let action: () -> Void

            @State private var isHovering: Bool = false

            var body: some View {
                Button(action: action) {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? ArchivePalette.accentWarm : ArchivePalette.inkMuted)
                            .frame(width: 18)
                        Text(section.title)
                            .font(ArchiveTypography.bodySans(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? ArchivePalette.inkPrimary : ArchivePalette.inkSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(rowFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(selected ? ArchivePalette.borderDivider : Color.clear, lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.14), value: selected)
                .animation(.easeOut(duration: 0.1), value: isHovering)
                .onHover { isHovering = $0 }
            }

            private var rowFill: Color {
                if selected { return ArchivePalette.archiveSubtle }
                return isHovering ? ArchivePalette.archiveSubtle.opacity(0.45) : .clear
            }
        }

}
