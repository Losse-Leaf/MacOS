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

        return VStack(spacing: 24) {
            // 顶部 App 英雄刊头 (Hero Banner)
            VStack(spacing: 12) {
                // 精致纸墨拟物 App 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [
                                    ArchivePalette.accentMoss.opacity(0.9),
                                    ArchivePalette.accentMoss
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                        .shadow(color: ArchivePalette.accentMoss.opacity(0.25), radius: 8, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(ArchivePalette.archivePaper.opacity(0.2), lineWidth: 1)
                        )

                    Image(systemName: "leaf.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(ArchivePalette.archivePaper)
                }
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text("Loose-Leaf · 活页集")
                        .font(ArchiveTypography.editorialSerif(size: 22, weight: .bold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Text("以纸为介，散页成卷 · 生活原色，自当留存")
                        .font(ArchiveTypography.editorialSerif(size: 12))
                        .foregroundStyle(ArchivePalette.inkSecondary)

                    // 100% 动态读取 Bundle 信息，绝不硬编码！
                    Text("版本 \(currentVersion) (Build \(currentBuild)) · 原生 Apple Silicon")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)

            // 1. 软件更新状态卡片 (Auto-Updater Card)
            settingsCardSection(title: "软件更新") {
                VStack(spacing: 0) {
                    if checker.isChecking {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("正在检查最新版本…")
                                    .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                Text("正在连接 GitHub Releases 官方源查询最新发布包")
                                    .font(ArchiveTypography.bodySans(size: 10.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            Spacer()
                        }
                        .padding(14)
                    } else if checker.isUpdating {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("正在下载并应用最新版本…")
                                    .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                                Text("正在下载更新归档并替换 /Applications/LooseLeaf.app")
                                    .font(ArchiveTypography.bodySans(size: 10.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            Spacer()
                        }
                        .padding(14)
                    } else if let update = checker.availableUpdate {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(ArchivePalette.accentWarm.opacity(0.15))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(ArchivePalette.accentWarm)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("发现新版本 \(update.tagName)")
                                        .font(ArchiveTypography.bodySans(size: 12.5, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                    Text("发布于 \(update.publishedAt)")
                                        .font(ArchiveTypography.monoScale(size: 10))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }

                                Spacer()

                                Button("立即更新并重启") {
                                    Task { @MainActor in
                                        await checker.performInAppUpdate()
                                    }
                                }
                                .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                            }

                            if !update.body.isEmpty {
                                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                                Text("更新日志：")
                                    .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                Text(update.body)
                                    .font(ArchiveTypography.monoScale(size: 10.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .lineLimit(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(14)
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
                            .font(ArchiveTypography.bodySans(size: 11))
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        }
                    }

                    if let updateError = checker.updateError, !updateError.isEmpty {
                        Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(ArchivePalette.accentWarm)
                            Text(updateError)
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)
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
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
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
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
            }

            // 3. 开源与链接 (Links & Community)
            settingsCardSection(title: "社区与协议") {
                settingsCardRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    iconColor: ArchivePalette.inkSecondary,
                    title: "GitHub 开源仓库",
                    subtitle: "github.com/Losse-Leaf/MacOS"
                ) {
                    Button {
                        if let url = URL(string: "https://github.com/Losse-Leaf/MacOS") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text("访问仓库")
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 9))
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }

                settingsRowDivider

                settingsCardRow(
                    icon: "bubble.left.and.exclamationmark.bubble.right",
                    iconColor: ArchivePalette.accentWarm,
                    title: "问题反馈与建议",
                    subtitle: "报告 Bug、提出改进建议或参与功能讨论"
                ) {
                    Button {
                        if let url = URL(string: "https://github.com/Losse-Leaf/MacOS/issues") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text("提交反馈")
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 9))
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
            }

            // 底部版权信息
            VStack(spacing: 4) {
                Text("Local-First 本地优先 · SQLite + R2 冗余热备")
                    .font(ArchiveTypography.monoScale(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Text("Copyright © 2024-2026 Loose-Leaf Contributors · MIT License")
                    .font(ArchiveTypography.monoScale(size: 9.5))
                    .foregroundStyle(ArchivePalette.inkMuted.opacity(0.8))
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }
}
