import SwiftUI

/// 账号与连接（独立 Settings 窗口「账号与连接」分页）：当前登录账号、同步服务器与退出登录
@MainActor
struct HubDevicesSettingsView: View {
    @Bindable var appState: AppState

    @State private var isSyncingNow: Bool = false
    @State private var feedbackMessage: String?
    @State private var errorMessage: String?
    @State private var showLogoutConfirm: Bool = false

    public init(appState: AppState) {
        self.appState = appState
    }

    private var displayAccountName: String {
        let candidates = [appState.accountName, appState.profile.name, appState.accountEmail, appState.profile.email ?? ""]
        for c in candidates {
            let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "Vesper Auth 账号"
    }

    private var displayAccountSubtitle: String {
        let email = [appState.accountEmail, appState.profile.email ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        if !email.isEmpty && email != displayAccountName {
            return "\(email) · Vesper Auth"
        }
        return "Vesper Auth 账号"
    }

    public var body: some View {
        let badge = appState.hubConnectionBadgeState

        VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
            settingsFeedbackBanner(feedback: feedbackMessage, error: errorMessage)

            // 1. 当前账号
            settingsCardSection(
                title: "当前账号",
                caption: appState.isPaired ? "已登录" : "未登录"
            ) {
                HStack(spacing: ArchiveSpacing.m) {
                    ZStack {
                        RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                            .fill(ArchivePalette.accentMoss.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.inkMuted)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                        HStack(spacing: ArchiveSpacing.s) {
                            Text(appState.isPaired ? displayAccountName : "未登录账号")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)

                            if appState.isPaired {
                                Text("已登录")
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                    .foregroundStyle(ArchivePalette.accentMoss)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(ArchivePalette.accentMoss.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            }
                        }

                        Text(appState.isPaired
                             ? displayAccountSubtitle
                             : "请在主窗口使用 Vesper Auth 登录你的账号")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    Spacer()

                    if appState.isPaired {
                        Button("退出登录") {
                            showLogoutConfirm = true
                        }
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                    }
                }
                .padding(ArchiveCardMetrics.padding)
            }

            // 2. 同步服务器连接状态
            settingsCardSection(
                title: "同步服务器",
                caption: appState.isPaired ? (appState.isOnline ? "连接正常" : "离线模式 · 发件箱就绪") : "未连接"
            ) {
                HStack(spacing: ArchiveSpacing.m) {
                    Circle()
                        .fill(badge.dotColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                        Text(appState.isPaired ? "云端同步 (\(badge.label))" : "未连接同步服务器")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)

                        Text(appState.hubURLString)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    Spacer()

                    if appState.isPaired {
                        Button {
                            Task { @MainActor in
                                await syncNow()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if isSyncingNow {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: ArchiveIcon.sync.systemName)
                                        .font(.system(size: 10.5))
                                }
                                Text("立即同步")
                            }
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .paperButtonFocusRing()
                        .disabled(isSyncingNow)
                    }
                }
                .padding(ArchiveCardMetrics.padding)
            }
        }
        .task {
            if appState.isPaired {
                await appState.refreshAccountSession()
            }
        }
        .alert("确认退出登录？", isPresented: $showLogoutConfirm) {
            Button("退出登录", role: .destructive) {
                Task { @MainActor in
                    await appState.disconnectDevice()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            let pending = appState.outboxItems.count
            let warning = pending > 0
                ? "\n\n注意：本机还有 \(pending) 条待同步记录，退出登录将连同清除且无法找回，建议先联网同步完成后再退出。"
                : ""
            Text("退出登录将清除本机登录状态、本地快照、图片缓存与 Spotlight 索引，下次通过 Vesper Auth 重新登录即可恢复同步。\(warning)")
        }
    }

    private func syncNow() async {
        isSyncingNow = true
        errorMessage = nil
        feedbackMessage = nil
        defer { isSyncingNow = false }
        await appState.refreshAll(forceFull: false)
        await appState.refreshAccountSession()
        feedbackMessage = "已完成云端同步"
    }
}
