import SwiftUI

/// 中枢与设备（左侧菜单「中枢与设备」入口）：配对门禁、受信任设备管理与重命名
@MainActor
struct HubDevicesSettingsView: View {
    @Bindable var appState: AppState

    @State private var ticketURIInput: String = ""
    @State private var isSubmittingAuth: Bool = false
    @State private var authFeedback: String?
    @State private var authError: String?

    // 签发新设备配对码状态
    @State private var issuedPairTicket: PairTicketResponse?

    // 设备重命名与吊销状态
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
            // 中枢连接状态
            settingsCardSection(title: "数据中枢连接", caption: appState.isPaired ? "已接入中枢网络" : "尚未配对") {
                HStack(spacing: ArchiveSpacing.m) {
                    Circle()
                        .fill(appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                        Text(appState.isPaired ? "数据中枢已连接" : "未配对中枢节点")
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

                    if appState.isPaired {
                        Button {
                            Task { @MainActor in
                                // 关键：失败必须**说出来**。
                                // 原先是 `try?` —— 网络或鉴权失败时票据保持 nil，
                                // 界面毫无变化，按钮像坏了一样，用户完全不知道发生了什么。
                                do {
                                    issuedPairTicket = try await APIClient.shared.initPairing()
                                    authError = nil
                                } catch {
                                    issuedPairTicket = nil
                                    authError = "签发配对凭证失败：\(error.localizedDescription)"
                                }
                            }
                        } label: {
                            HStack(spacing: ArchiveSpacing.xs) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 11))
                                    .accessibilityHidden(true)
                                Text("签发新设备配对凭证")
                            }
                        }
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    }
                }
                .padding(ArchiveCardMetrics.padding)

                // 未配对时的凭证导入行
                if !appState.isPaired {
                    Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                    unpairedInputBar
                        .padding(ArchiveCardMetrics.padding)
                }

                // 配对工单二维码卡片 (若已生成)
                if let ticket = issuedPairTicket {
                    Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                    pairTicketBanner(ticket: ticket)
                        .padding(ArchiveCardMetrics.padding)
                }
            }

            // 本机客户端置顶展示
            let currentDeviceId = CredentialStore.getDeviceId()
            let selfDev = appState.trustedDevices.first(where: { $0.deviceId == currentDeviceId })
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
                        appState.askConfirm(
                            title: "确认解除本机配对？",
                            message: "解除配对将删除本机以 0600 权限保存的凭据档案 (credentials.json)，需重新扫码配对才能接入中枢。",
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

            // 受信任伴生设备组
            let otherDevices = appState.trustedDevices.filter { $0.deviceId != currentDeviceId }
            settingsCardSection(title: "已授权伴生设备 (\(otherDevices.count))", footer: "所有已配对伴生设备享有端到端生活档案同步权限，可随时吊销授权。") {
                if otherDevices.isEmpty {
                    ArchiveEmptyState(
                        systemName: "iphone.and.arrow.forward",
                        title: "暂无其他已配对伴生设备",
                        message: "点击上方「签发新设备配对凭证」，即可在手机或 Web 端扫码接入中枢。"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(otherDevices.enumerated()), id: \.element.id) { index, dev in
                            if index > 0 {
                                settingsRowDivider
                            }
                            HStack(spacing: ArchiveSpacing.m) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                                        .fill(ArchivePalette.inkSecondary.opacity(0.1))
                                        .frame(width: ArchiveHitTarget.minPointer, height: ArchiveHitTarget.minPointer)
                                    Image(systemName: devicePlatformIcon(dev.platform, isSelf: false))
                                        .font(.system(size: 13))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .accessibilityHidden(true)
                                }

                                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                    HStack(spacing: ArchiveSpacing.s) {
                                        Text(dev.name)
                                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        Text(dev.platform)
                                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                            .padding(.horizontal, ArchiveSpacing.xs)
                                            .padding(.vertical, 1)
                                            .background(ArchivePalette.archivePaper)
                                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                    }
                                    Text("最近活跃：\(FormatUtils.parseOccurredDate(dev.lastActiveAt).dotDateTime)")
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }

                                Spacer()

                                Button("重命名") {
                                    renamingDevice = dev
                                    newDeviceNameInput = dev.name
                                }
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                                .buttonStyle(.plain)

                                Button("吊销授权") {
                                    appState.askConfirm(
                                        title: "确认吊销该设备的接入授权？",
                                        message: "吊销后该伴生设备将无法继续同步或读取中枢生活档案。",
                                        confirmText: "吊销设备凭证",
                                        danger: true
                                    ) {
                                        revokeDeviceAction(dev)
                                    }
                                }
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, ArchiveCardMetrics.padding)
                            .padding(.vertical, 10)
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
    private func devicePlatformIcon(_ platform: String, isSelf: Bool) -> String {
        if isSelf { return "laptopcomputer" }
        let p = platform.lowercased()
        if p.contains("mac") { return "laptopcomputer" }
        if p.contains("android") { return "phone" }
        if p.contains("ios") || p.contains("iphone") { return "iphone" }
        if p.contains("web") { return "globe" }
        return "desktopcomputer"
    }


    private var unpairedInputBar: some View {
        HStack(spacing: ArchiveSpacing.s) {
            TextField("输入或粘贴配对工单号 (Ticket) 或深链…", text: $ticketURIInput)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                .accessibilityLabel("配对工单号或深链输入框")

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
            .disabled(ticketURIInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingAuth)
            .help("使用工单号免密接入中枢")
        }
    }


    private func pairTicketBanner(ticket: PairTicketResponse) -> some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
            HStack {
                Text("新设备配对凭证（5 分钟内有效）")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                Button("收起") {
                    issuedPairTicket = nil
                }
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                .buttonStyle(.plain)
                .foregroundStyle(ArchivePalette.inkMuted)
            }

            HStack(spacing: ArchiveSpacing.m) {
                if let qrImg = decodeDataURLImage(ticket.qrCodeDataUrl) {
                    Image(nsImage: qrImg)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .padding(ArchiveSpacing.xs)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                        .accessibilityLabel("新设备配对二维码")
                }

                VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                    Text(ticket.qrPayload)
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ticket.qrPayload, forType: .string)
                        appState.showTemporaryBanner("已复制配对链接")
                    } label: {
                        HStack(spacing: ArchiveSpacing.xs) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .accessibilityHidden(true)
                            Text("复制配对链接")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
            }
        }
        .padding(ArchiveSpacing.s)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
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

    private func revokeDeviceAction(_ dev: TrustedDevice) {
        Task { @MainActor in
            do {
                try await APIClient.shared.revokeDevice(id: dev.deviceId)
                authFeedback = "设备「\(dev.name)」已吊销"
            } catch {
                authError = error.localizedDescription
            }
            await refreshDevicesList()
        }
    }


    private func decodeDataURLImage(_ dataURL: String?) -> NSImage? {
        guard let dataURL, let commaIdx = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: commaIdx)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }

}
