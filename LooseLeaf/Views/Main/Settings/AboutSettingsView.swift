import SwiftUI

/// 关于活页（左侧菜单「关于活页」入口）：版本状态、更新检查与系统诊断
@MainActor
struct AboutSettingsView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        let currentVersion = UpdateChecker.shared.currentVersion
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let checker = UpdateChecker.shared

        return VStack(spacing: ArchiveSpacing.l) {
            // 顶部 App 英雄刊头 (Hero Banner)
            VStack(spacing: ArchiveSpacing.m) {
                // 真实 App 图标：与 Dock / 访达中展示的 AppIcon 完全一致
                appIconView
                    .padding(.top, ArchiveSpacing.s)

                VStack(spacing: ArchiveSpacing.xs) {
                    Text("Loose-Leaf · 活页集")
                        .font(ArchiveTypography.editorialSerif(size: Self.heroTitleSize, weight: .bold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Text("以纸为介，散页成卷 · 生活原色，自当留存")
                        .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.body))
                        .foregroundStyle(ArchivePalette.inkSecondary)

                    // 100% 动态读取 Bundle 信息，绝不硬编码！
                    Text("版本 \(currentVersion) (Build \(currentBuild)) · 原生 Apple Silicon")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(.top, ArchiveSpacing.xxs)
                }
            }
            .frame(maxWidth: .infinity)

            // 1. 软件更新状态卡片 (Auto-Updater Card)
            settingsCardSection(title: "软件更新") {
                VStack(spacing: 0) {
                    if checker.isChecking {
                        HStack(spacing: ArchiveSpacing.m) {
                            ProgressView().controlSize(.small)
                            VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                Text("正在检查最新版本…")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                Text("正在连接 GitHub Releases 官方源查询最新发布包")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            Spacer()
                        }
                        .padding(ArchiveCardMetrics.padding)
                    } else if checker.isUpdating {
                        HStack(spacing: ArchiveSpacing.m) {
                            ProgressView().controlSize(.small)
                            VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                Text("正在下载并应用最新版本…")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                                Text("正在下载更新归档并替换 /Applications/LooseLeaf.app")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            Spacer()
                        }
                        .padding(ArchiveCardMetrics.padding)
                    } else if let update = checker.availableUpdate {
                        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                            HStack(spacing: ArchiveSpacing.m) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                                        .fill(ArchivePalette.accentWarm.opacity(0.15))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                }

                                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                    Text("发现新版本 \(update.tagName)")
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                    Text("发布于 \(update.publishedAt)")
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }

                                Spacer()

                                Button("立即更新并重启") {
                                    Task { @MainActor in
                                        await checker.performInAppUpdate()
                                    }
                                }
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                                .paperButtonFocusRing()
                            }

                            if !update.body.isEmpty {
                                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                                Text("更新日志：")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                Text(update.body)
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .lineLimit(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(ArchiveSpacing.s)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            }
                        }
                        .padding(ArchiveCardMetrics.padding)
                    } else {
                        settingsCardRow(
                            icon: "checkmark.seal.fill",
                            iconColor: ArchivePalette.accentMoss,
                            title: "当前已是最新版本 (v\(currentVersion))",
                            subtitle: "Loose-Leaf 已同步至官方最新稳定发行版"
                        ) {
                            Button("重新检查更新") {
                                Task { @MainActor in
                                    await checker.checkForUpdates(isUserInitiated: true)
                                }
                            }
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .paperButtonFocusRing()
                        }
                    }

                    if let updateError = checker.updateError, !updateError.isEmpty {
                        Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                        // 更新失败原因（沙箱拦截 / 无 /Applications 写权限等）必须可见
                        settingsFeedbackBanner(feedback: nil, error: updateError)
                            .padding(ArchiveCardMetrics.padding)
                    }
                }
            }

            // 2. 系统与环境诊断 (Diagnostic Information)
            settingsCardSection(title: "系统与环境") {
                settingsCardRow(
                    icon: "apple.logo",
                    iconColor: ArchivePalette.inkSecondary,
                    title: "运行环境",
                    subtitle: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · 原生 Apple Silicon (arm64)"
                ) {
                    EmptyView()
                }

                settingsRowDivider

                settingsCardRow(
                    icon: "server.rack",
                    iconColor: appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm,
                    title: "数据中枢",
                    subtitle: appState.isPaired ? appState.hubURLString : "未配对中枢 (单机离线状态)"
                ) {
                    Text(appState.isPaired ? "已连接" : "离线")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                settingsRowDivider

                settingsCardRow(
                    icon: "externaldrive.fill",
                    iconColor: ArchivePalette.inkSecondary,
                    title: "本地存储缓存",
                    subtitle: "散页 \(appState.entries.count) 篇 · 账目 \(appState.transactions.count) 笔 · 待发 \(appState.outboxItems.count) 项"
                ) {
                    Button("在访达中显示") {
                        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                            let looseLeafDir = appSupport.appendingPathComponent("LooseLeaf")
                            try? FileManager.default.createDirectory(at: looseLeafDir, withIntermediateDirectories: true)
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: looseLeafDir.path)
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                }
            }

            // 3. 开源与链接 (Links & Community)
            settingsCardSection(title: "社区与协议") {
                settingsCardRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    iconColor: ArchivePalette.inkSecondary,
                    title: "GitHub 开源仓库",
                    subtitle: "github.com/\(UpdateChecker.repo)"
                ) {
                    Button {
                        if let url = URL(string: "https://github.com/\(UpdateChecker.repo)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: ArchiveSpacing.xs) {
                            Text("访问仓库")
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 10))
                                .accessibilityHidden(true)
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                }

                settingsRowDivider

                settingsCardRow(
                    icon: "bubble.left.and.exclamationmark.bubble.right",
                    iconColor: ArchivePalette.accentWarm,
                    title: "问题反馈与建议",
                    subtitle: "报告 Bug、提出改进建议或参与功能讨论"
                ) {
                    Button {
                        if let url = URL(string: "https://github.com/\(UpdateChecker.repo)/issues") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: ArchiveSpacing.xs) {
                            Text("提交反馈")
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 10))
                                .accessibilityHidden(true)
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                }
            }

            // 底部版权信息
            VStack(spacing: ArchiveSpacing.xs) {
                Text("Local-First 本地优先 · SQLite + R2 冗余热备")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Text("Copyright © 2024-2026 Loose-Leaf Contributors · MIT License")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                    .foregroundStyle(ArchivePalette.inkMuted.opacity(0.8))
            }
            .padding(.top, ArchiveSpacing.xs)
            .padding(.bottom, ArchiveSpacing.xl)
        }
    }

    // MARK: - 真实 App 图标

    /// 刊头主标题字号（介于 Scale.title 与 Scale.display 之间的英雄级排版）
    private static let heroTitleSize: CGFloat = 22

    /// 真实 App 图标：与 Dock / 访达中展示的 AppIcon 完全一致。
    /// 优先取资产目录中的 `AppIcon`；若运行环境下不可用则回退到系统提供的应用图标。
    private var appIconView: some View {
        Group {
            if Self.hasBundledAppIcon {
                Image("AppIcon", bundle: ArchiveResourceBundle.bundle)
                    .resizable()
                    .interpolation(.high)
            } else if let fallbackIcon = NSApp.applicationIconImage {
                Image(nsImage: fallbackIcon)
                    .resizable()
                    .interpolation(.high)
            } else {
                // 兜底：极简纸墨叶形，避免出现空白方块
                ZStack {
                    ArchivePalette.accentMoss
                    Image(systemName: "leaf.fill")
                        .resizable()
                        .interpolation(.high)
                        .padding(Self.appIconSize * 0.28)
                        .foregroundStyle(ArchivePalette.archivePaper)
                }
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: Self.appIconSize, height: Self.appIconSize)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.lg))
        .shadow(color: ArchivePalette.accentMoss.opacity(0.25), radius: 8, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.lg)
                .stroke(ArchivePalette.archivePaper.opacity(0.2), lineWidth: 1)
        )
        .accessibilityLabel("Loose-Leaf 应用图标")
    }

    /// App 图标边长
    private static let appIconSize: CGFloat = 76

    /// 缓存的 AppIcon 资源（避免每次布局都做一次资源查找）
    private static let bundledAppIcon: NSImage? = ArchiveResourceBundle.bundle.image(forResource: "AppIcon")

    /// 运行环境下是否存在可用的 AppIcon 资源
    private static var hasBundledAppIcon: Bool {
        bundledAppIcon != nil
    }
}
