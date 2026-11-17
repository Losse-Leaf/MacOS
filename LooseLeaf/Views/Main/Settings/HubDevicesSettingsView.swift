import SwiftUI

/// 中枢与设备（独立 Settings 窗口「中枢与设备」分页）：中枢状态、本机解绑与全量受信任设备管理
@MainActor
struct HubDevicesSettingsView: View {
    @Bindable var appState: AppState

    @State private var authFeedback: String?
    @State private var authError: String?
    @State private var isRefreshingDevices: Bool = false

    // 设备重命名状态
    @State private var renamingDevice: TrustedDevice?
    @State private var newDeviceNameInput: String = ""
    @State private var isRenamingDevice: Bool = false
    @State private var renameError: String?
    @FocusState private var isRenameFieldFocused: Bool

    public init(appState: AppState) {
        self.appState = appState
    }

    private func platformIcon(for platform: String) -> String {
        switch platform.lowercased() {
        case "macos", "mac": return "laptopcomputer"
        case "android", "ios", "mobile": return "iphone"
        case "ipad": return "ipad"
        default: return "desktopcomputer"
        }
    }

    private func platformLabel(for dev: TrustedDevice) -> String {
        let model = (dev.deviceModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let activeDot = FormatUtils.parseOccurredDate(dev.lastActiveAt).dotDateTime
        let base: String
        switch dev.platform.lowercased() {
        case "macos", "mac": base = model.isEmpty ? "macOS 客户端" : "macOS · \(model)"
        case "android": base = model.isEmpty ? "Android 客户端" : "Android · \(model)"
        case "web": base = "Web 展厅管理端"
        default: base = model.isEmpty ? dev.platform : model
        }
        return activeDot.isEmpty ? base : "\(base) · 最近活跃 \(activeDot)"
    }

    public var body: some View {
        let badge = appState.hubConnectionBadgeState
        let currentDeviceId = CredentialStore.getDeviceId()
        let selfDev = appState.trustedDevices.first(where: { $0.isCurrent == true || $0.deviceId == currentDeviceId })
        let otherDevices = appState.trustedDevices.filter { dev in
            if let selfDev { return dev.deviceId != selfDev.deviceId }
            if let currentDeviceId { return dev.deviceId != currentDeviceId }
            return dev.isCurrent != true
        }

        VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
            settingsFeedbackBanner(feedback: authFeedback, error: authError)

            // 1. 中枢连接状态
            settingsCardSection(
                title: "数据中枢连接",
                caption: appState.isPaired ? (appState.isOnline ? "已接入中枢网络" : "中枢离线 · 发件箱就绪") : "尚未配对"
            ) {
                HStack(spacing: ArchiveSpacing.m) {
                    Circle()
                        .fill(badge.dotColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                        Text(appState.isPaired ? "数据中枢节点 (\(badge.label))" : "未配对中枢节点")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)

                        Text(appState.isPaired
                             ? appState.hubURLString
                             : "请在主窗口配对门禁页输入工单号或使用配对深链完成首次握手")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    Spacer()

                    if appState.isPaired {
                        Button {
                            Task { @MainActor in
                                await refreshDevicesList()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if isRefreshingDevices {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: ArchiveIcon.sync.systemName)
                                        .font(.system(size: 10.5))
                                }
                                Text("刷新设备")
                            }
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .paperButtonFocusRing()
                        .disabled(isRefreshingDevices)
                    }
                }
                .padding(ArchiveCardMetrics.padding)
            }

            if appState.isPaired {
                // 2. 本机客户端置顶展示
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
                            Text(selfDev.map(platformLabel(for:)) ?? "macOS 原生客户端 · 当前在线")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }

                        Spacer()

                        if let selfDev {
                            Button("重命名") {
                                renameError = nil
                                newDeviceNameInput = selfDev.name
                                renamingDevice = selfDev
                            }
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .paperButtonFocusRing()
                        }

                        Button("解除配对") {
                            let pending = appState.outboxItems.count
                            let warning = pending > 0
                                ? "\n\n注意：本机还有 \(pending) 条待同步记录，解绑将连同清除且无法找回，建议先联网同步完成后再操作。"
                                : ""
                            appState.askConfirm(
                                title: "确认解除本机配对？",
                                message: "解除配对将向中枢吊销本机授权令牌，并彻底清除本机私密快照、相纸缓存、Spotlight 索引与接力状态。\(warning)",
                                confirmText: "解除配对并清除本机缓存",
                                danger: true
                            ) {
                                Task { @MainActor in
                                    await appState.disconnectDevice()
                                }
                            }
                        }
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .buttonStyle(.plain)
                        .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                    }
                    .padding(ArchiveCardMetrics.padding)
                }

                // 3. 其他已授权受信任设备列表（支持重命名与远程吊销）
                settingsCardSection(
                    title: "其他已授权设备 (\(otherDevices.count))",
                    footer: "吊销某台设备的授权后，该设备下次联网时会自动退回配对门禁并清空其本地私密快照。"
                ) {
                    if otherDevices.isEmpty {
                        HStack {
                            Text("当前中枢下暂无其他已配对的跨端设备")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkMuted)
                            Spacer()
                        }
                        .padding(ArchiveCardMetrics.padding)
                    } else {
                        ForEach(Array(otherDevices.enumerated()), id: \.element.id) { index, dev in
                            if index > 0 {
                                settingsRowDivider
                            }
                            HStack(spacing: ArchiveSpacing.m) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                                        .fill(ArchivePalette.inkSecondary.opacity(0.10))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: platformIcon(for: dev.platform))
                                        .font(.system(size: 14))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .accessibilityHidden(true)
                                }

                                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                    Text(dev.name)
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                    Text(platformLabel(for: dev))
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }

                                Spacer()

                                Button("重命名") {
                                    renameError = nil
                                    newDeviceNameInput = dev.name
                                    renamingDevice = dev
                                }
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                                .paperButtonFocusRing()

                                Button("吊销授权") {
                                    appState.askConfirm(
                                        title: "吊销设备「\(dev.name)」？",
                                        message: "吊销后该设备的访问令牌立即失效，需重新配对才能再次访问档案。",
                                        confirmText: "确认吊销",
                                        danger: true
                                    ) {
                                        revokeOtherDevice(dev)
                                    }
                                }
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .buttonStyle(.plain)
                                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                            }
                            .padding(ArchiveCardMetrics.padding)
                        }
                    }
                }
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

    private func renameDeviceSheetView(dev: TrustedDevice) -> some View {
        PaperSheetScaffold(
            title: "重命名设备",
            width: ArchiveSheetWidth.compact,
            isSubmitting: isRenamingDevice,
            isSubmitDisabled: newDeviceNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            submitTitle: "保存修改 ⌘↩",
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
                    .focused($isRenameFieldFocused)
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading))
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .accessibilityLabel("设备名称")

                settingsFeedbackBanner(feedback: nil, error: renameError)
            }
        }
        .onAppear {
            isRenameFieldFocused = true
        }
    }

    private func performRename(_ dev: TrustedDevice) {
        let targetId = dev.deviceId
        let newName = newDeviceNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, !isRenamingDevice else { return }
        isRenamingDevice = true
        renameError = nil
        Task { @MainActor in
            defer { isRenamingDevice = false }
            do {
                _ = try await APIClient.shared.updateDeviceName(id: targetId, name: newName)
                renamingDevice = nil
                authError = nil
                authFeedback = "设备「\(newName)」已重命名"
                await refreshDevicesList()
            } catch {
                renameError = "重命名失败：\(error.localizedDescription)"
            }
        }
    }

    private func revokeOtherDevice(_ dev: TrustedDevice) {
        authError = nil
        authFeedback = nil
        Task { @MainActor in
            do {
                try await APIClient.shared.revokeDevice(id: dev.deviceId)
                authFeedback = "已吊销设备「\(dev.name)」的访问授权"
                await refreshDevicesList()
            } catch {
                authError = "吊销设备失败：\(error.localizedDescription)"
            }
        }
    }

    private func refreshDevicesList() async {
        isRefreshingDevices = true
        defer { isRefreshingDevices = false }
        do {
            let list = try await APIClient.shared.fetchTrustedDevices()
            appState.trustedDevices = list

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
            authError = "获取设备列表失败：\(error.localizedDescription)"
        }
    }
}
