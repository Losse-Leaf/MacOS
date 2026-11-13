import SwiftUI

/// 中枢与设备（左侧菜单「中枢与设备」入口）：配对门禁、受信任设备管理与重命名
@MainActor
struct HubDevicesSettingsView: View {
    @Bindable var appState: AppState

    @State private var ticketURIInput: String = ""
    @State private var isSubmittingAuth: Bool = false
    @State private var authFeedback: String?
    @State private var authError: String?

    // 设备重命名状态
    @State private var renamingDevice: TrustedDevice?
    @State private var newDeviceNameInput: String = ""
    @State private var isRenamingDevice: Bool = false
    @State private var renameError: String?

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
            settingsFeedbackBanner(feedback: authFeedback, error: authError)
            let badge = appState.hubConnectionBadgeState
            // 中枢连接状态
            settingsCardSection(title: "数据中枢连接", caption: appState.isPaired ? (appState.isOnline ? "已接入中枢网络" : "中枢离线 · 发件箱就绪") : "尚未配对") {
                HStack(spacing: ArchiveSpacing.m) {
                    Circle()
                        .fill(badge.dotColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                        Text(appState.isPaired ? "数据中枢节点 (\(badge.label))" : "未配对中枢节点")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                                                // 关键：文案要与**事实**相符。
                        // 原文写「实时同步」，但客户端**没有任何推送或轮询** ——
                        // 全仓没有 Timer / WebSocket / SSE，实际同步只发生在
                        // 冷启动、用户按 ⌘R、以及提交后自动上传三处。
                        Text(appState.isPaired
                             ? appState.hubURLString
                             : "配对后可跨设备多端同步散页与财务资产（⌘R 手动同步，提交后自动上传）")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    Spacer()
                }
                .padding(ArchiveCardMetrics.padding)

                // 未配对时的凭证导入行
                if !appState.isPaired {
                    Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                    unpairedInputBar
                        .padding(ArchiveCardMetrics.padding)
                }
            }

            // 本机客户端置顶展示
            let currentDeviceId = CredentialStore.getDeviceId()
            let selfDev = appState.trustedDevices.first(where: { $0.isCurrent == true || $0.deviceId == currentDeviceId })
            settingsCardSection(title: "当前使用的设备") {
                HStack(spacing: ArchiveSpacing.m) {
                    ZStack {
                        RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                            .fill(ArchivePalette.accentMoss.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 16))
                            .foregroundStyle(ArchivePalette.accentMoss)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                        HStack(spacing: ArchiveSpacing.s) {
                            Text(selfDev?.name ?? "我的 Mac")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            Text("本机 · 当前客户端")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                .foregroundStyle(ArchivePalette.accentMoss)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(ArchivePalette.accentMoss.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                        }
                        Text("macOS 原生客户端 · 刚刚活跃")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    Spacer()

                    if let selfDev {
                        Button("重命名") {
                            renamingDevice = selfDev
                            newDeviceNameInput = selfDev.name
                        }
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .buttonStyle(.plain)
                    }

                    Button("解除配对") {
                        // 与 Android 端解绑确认同口径：有未同步记录时明确警告将被丢弃
                        let pending = appState.outboxItems.count
                        let warning = pending > 0
                            ? "注意：本机还有 \(pending) 条待同步记录（含离线日记/账目/相纸），解绑将连同删除且无法找回。建议先联网同步完成后再解绑。"
                            : ""
                        appState.askConfirm(
                            title: "确认解除本机配对？",
                            message: "解除配对将删除本机以 0600 权限保存的凭据档案 (credentials.json)，需重新扫码配对才能接入中枢。\(warning)",
                            confirmText: "解除配对并退出",
                            danger: true
                        ) {
                            Task { @MainActor in
                                await appState.disconnectDevice()
                            }
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .buttonStyle(.plain)
                }
                .padding(ArchiveCardMetrics.padding)
            }
        }
        .sheet(item: $renamingDevice) { dev in
            renameDeviceSheetView(dev: dev)
        }
        .task {
            if appState.isPaired {
                await refreshDevicesList()
            }
        }
    }

    private var unpairedInputBar: some View {
        HStack(spacing: ArchiveSpacing.s) {
            TextField("输入或粘贴配对工单号 (Ticket) 或深链…", text: $ticketURIInput)
                .accessibilityLabel("配对工单号或深链输入框")
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            Button {
                performTicketPairing()
            } label: {
                HStack(spacing: ArchiveSpacing.xs) {
                    if isSubmittingAuth {
                        ProgressView().controlSize(.small)
                    }
                    Text(isSubmittingAuth ? "正在配对…" : "立即免密配对")
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
            .disabled(ticketURIInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingAuth)
            .help("使用工单号免密接入中枢")
        }
    }

    /// 设备重命名弹窗：统一 Sheet 骨架，错误就地渲染
    private func renameDeviceSheetView(dev: TrustedDevice) -> some View {
        PaperSheetScaffold(
            title: "重命名设备",
            width: ArchiveSheetWidth.compact,
            isSubmitting: isRenamingDevice,
            submitTitle: "保存修改",
            onCancel: {
                renamingDevice = nil
                renameError = nil
            },
            onSubmit: {
                performRename(dev)
            }
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                TextField("设备名称", text: $newDeviceNameInput)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading))
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .accessibilityLabel("设备名称")

                settingsFeedbackBanner(feedback: nil, error: renameError)
            }
        }
    }

    /// 提交设备重命名（错误就地展示在弹窗内，避免被弹窗遮挡）
    private func performRename(_ dev: TrustedDevice) {
        let targetId = dev.deviceId
        let newName = newDeviceNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        isRenamingDevice = true
        renameError = nil
        Task { @MainActor in
            defer { isRenamingDevice = false }
            do {
                _ = try await APIClient.shared.updateDeviceName(id: targetId, name: newName)
                renamingDevice = nil
                authFeedback = "设备「\(newName)」已重命名"
                await refreshDevicesList()
            } catch {
                renameError = "重命名失败: \(error.localizedDescription)"
            }
        }
    }


    private func performTicketPairing() {
        let raw = ticketURIInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isSubmittingAuth = true
        authError = nil
        Task { @MainActor in
            do {
                if raw.hasPrefix("looseleaf://") {
                    guard let parsed = AppState.parsePairLink(raw) else {
                        authError = "无法识别配对链接，请在网页后台复制配对链接后重试"
                        isSubmittingAuth = false
                        return
                    }
                    let hub = parsed.hub.isEmpty ? appState.hubURLString : parsed.hub
                    try await appState.pairWithTicket(parsed.ticket, hubURL: hub)
                } else {
                    try await appState.pairWithTicket(raw, hubURL: appState.hubURLString)
                }
                ticketURIInput = ""
                authFeedback = "配对成功！设备令牌已安全托管于本机。"
                await refreshDevicesList()
            } catch {
                authError = error.localizedDescription
            }
            isSubmittingAuth = false
        }
    }


    private func refreshDevicesList() async {
        do {
            let list = try await APIClient.shared.fetchTrustedDevices()
            appState.trustedDevices = list

            // 自愈机制：若当前 Mac 客户端在历史版本中被后端误登记为 "web"，自动修正为 "macos"
            let myDeviceId = CredentialStore.getDeviceId()
            if let selfDev = list.first(where: { $0.deviceId == myDeviceId }), selfDev.platform.lowercased() != "macos" {
                Task {
                    _ = try? await APIClient.shared.updateDeviceName(
                        id: selfDev.deviceId,
                        name: selfDev.name,
                        platform: "macos",
                        deviceModel: "Mac"
                    )
                    if let updated = try? await APIClient.shared.fetchTrustedDevices() {
                        await MainActor.run {
                            appState.trustedDevices = updated
                        }
                    }
                }
            }
        } catch {
            // 拉不到设备列表也要说清楚，而不是静默留着一份旧列表
            authError = "获取设备列表失败：\(error.localizedDescription)"
        }
    }

}
