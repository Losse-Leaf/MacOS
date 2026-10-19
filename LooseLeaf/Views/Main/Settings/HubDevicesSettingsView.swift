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

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 20) {
            // 中枢连接状态
            settingsCardSection(title: "数据中枢连接", caption: appState.isPaired ? "已接入中枢网络" : "尚未配对") {
                HStack(spacing: 12) {
                    Circle()
                        .fill(appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.isPaired ? "数据中枢已连接" : "未配对中枢节点")
                            .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text(appState.isPaired ? appState.hubURLString : "配对后可跨设备多端实时同步散页与财务资产")
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    Spacer()

                    if appState.isPaired {
                        Button {
                            Task { @MainActor in
                                issuedPairTicket = try? await APIClient.shared.initPairing()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 11))
                                Text("签发新设备配对凭证")
                            }
                        }
                        .font(ArchiveTypography.bodySans(size: 11))
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    }
                }
                .padding(14)

                // 未配对时的凭证导入行
                if !appState.isPaired {
                    Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                    unpairedInputBar
                        .padding(12)
                }

                // 配对工单二维码卡片 (若已生成)
                if let ticket = issuedPairTicket {
                    Divider().overlay(ArchivePalette.borderSubtle.opacity(0.5))
                    pairTicketBanner(ticket: ticket)
                        .padding(12)
                }
            }

            // 本机客户端置顶展示
            let currentDeviceId = CredentialStore.getDeviceId()
            let selfDev = appState.trustedDevices.first(where: { $0.deviceId == currentDeviceId })
            settingsCardSection(title: "当前使用的设备") {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ArchivePalette.accentMoss.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 16))
                            .foregroundStyle(ArchivePalette.accentMoss)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(selfDev?.name ?? "我的 Mac")
                                .font(ArchiveTypography.bodySans(size: 13, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            Text("本机 · 当前客户端")
                                .font(ArchiveTypography.monoScale(size: 9.5))
                                .foregroundStyle(ArchivePalette.accentMoss)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(ArchivePalette.accentMoss.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text("macOS 原生客户端 · 刚刚活跃")
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    Spacer()

                    if let selfDev {
                        Button("重命名") {
                            renamingDevice = selfDev
                            newDeviceNameInput = selfDev.name
                        }
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .buttonStyle(.plain)
                    }

                    Button("解除配对") {
                        appState.askConfirm(
                            title: "确认解除本机配对？",
                            message: "解除配对将清空保存在本机钥匙串的受保护凭据，需重新扫码配对才能接入中枢。",
                            confirmText: "解除配对并退出",
                            danger: true
                        ) {
                            Task { @MainActor in
                                await appState.disconnectDevice()
                            }
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                    .buttonStyle(.plain)
                }
                .padding(14)
            }

            // 受信任伴生设备组
            let otherDevices = appState.trustedDevices.filter { $0.deviceId != currentDeviceId }
            settingsCardSection(title: "已授权伴生设备 (\(otherDevices.count))", footer: "所有已配对伴生设备享有端到端生活档案同步权限，可随时吊销授权。") {
                if otherDevices.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "iphone.and.arrow.forward")
                                .font(.system(size: 20))
                                .foregroundStyle(ArchivePalette.inkMuted)
                            Text("暂无其他已配对伴生设备，点击上方「签发新设备配对凭证」可在手机或 Web 端扫码接入。")
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(otherDevices.enumerated()), id: \.element.id) { index, dev in
                            if index > 0 {
                                settingsRowDivider
                            }
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(ArchivePalette.inkSecondary.opacity(0.1))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: devicePlatformIcon(dev.platform, isSelf: false))
                                        .font(.system(size: 13))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(dev.name)
                                            .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        Text(dev.platform)
                                            .font(ArchiveTypography.monoScale(size: 9))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(ArchivePalette.archivePaper)
                                            .clipShape(RoundedRectangle(cornerRadius: 2))
                                    }
                                    Text("最近活跃：\(FormatUtils.parseOccurredDate(dev.lastActiveAt).dotDateTime)")
                                        .font(ArchiveTypography.monoScale(size: 9.5))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }

                                Spacer()

                                Button("重命名") {
                                    renamingDevice = dev
                                    newDeviceNameInput = dev.name
                                }
                                .font(ArchiveTypography.bodySans(size: 11))
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
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ArchivePalette.archivePaper)
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
        HStack(spacing: 8) {
            TextField("输入或粘贴配对工单号 (Ticket) 或深链…", text: $ticketURIInput)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 12))
                .padding(6)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Button("立即免密配对") {
                performTicketPairing()
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .disabled(ticketURIInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingAuth)
        }
    }


    private func pairTicketBanner(ticket: PairTicketResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("新设备配对凭证（5 分钟内有效）")
                    .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                Button("收起") {
                    issuedPairTicket = nil
                }
                .font(ArchiveTypography.bodySans(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(ArchivePalette.inkMuted)
            }

            HStack(spacing: 12) {
                if let qrImg = decodeDataURLImage(ticket.qrCodeDataUrl) {
                    Image(nsImage: qrImg)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .padding(4)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(ticket.qrPayload)
                        .font(ArchiveTypography.monoScale(size: 10))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ticket.qrPayload, forType: .string)
                        appState.showTemporaryBanner("已复制配对链接")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                            Text("复制配对链接")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
            }
        }
        .padding(10)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func renameDeviceSheetView(dev: TrustedDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名设备")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("设备名称", text: $newDeviceNameInput)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 12.5))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Button("取消") { renamingDevice = nil }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存修改") {
                    let targetId = dev.deviceId
                    let newName = newDeviceNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    renamingDevice = nil
                    Task { @MainActor in
                        do {
                            _ = try await APIClient.shared.updateDeviceName(id: targetId, name: newName)
                            await refreshDevicesList()
                        } catch {
                            authError = "重命名失败: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(newDeviceNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 300)
        .background(ArchivePalette.archivePaper)
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
        if let list = try? await APIClient.shared.fetchTrustedDevices() {
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
