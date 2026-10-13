import SwiftUI
import Carbon

/// 设备免密配对、本机凭据托管与偏好设置视图 (SettingsView)
/// 严格遵循 docs/macos.md §5 与 docs/backend.md §3 & §5.6 规范
@MainActor
public struct SettingsView: View {
    @Bindable var appState: AppState

    public enum PairingMethod: String, CaseIterable {
        case passcode = "主理人密钥授权"
        case ticketURI = "配对链接"
    }

    @State private var selectedMethod: PairingMethod = .ticketURI
    @State private var passcodeInput: String = ""
    @State private var ticketURIInput: String = ""
    @State private var isSubmittingAuth: Bool = false
    @State private var authFeedback: String?
    @State private var authError: String?

    // 健康探针与签发新设备配对码状态
    @State private var healthResult: HealthCheckResponse?
    @State private var issuedPairTicket: PairTicketResponse?
    @State private var isLoadingDevices: Bool = false

    // 全局热键录制状态
    @State private var hotKeyLabel: String = AppDelegate.hotKeyDisplayName
    @State private var isRecordingHotKey: Bool = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                // 1. 后端中枢地址与连通探针
                hubConnectionCard

                // 2. 设备免密配对与本机凭据管理
                devicePairingCard

                // 3. 已授信设备列表与发起移动端配对 (仅已配对时展示)
                if appState.isPaired {
                    trustedDevicesCard
                }

                // 4. 视觉模式、拟物声学与触控板反馈设置
                preferencesCard

                // 5. 本地优先缓存与离线发件箱状态
                localSyncCard
            }
            .padding(24)
        }
        .task {
            if appState.isPaired {
                await refreshDevicesList()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设备免密配对、本机凭据托管与偏好设置")
                .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
            Text("设备凭证存储于本机受保护档案（仅当前 macOS 用户可读写）")
                .font(ArchiveTypography.bodySans(size: 12.5))
                .foregroundStyle(ArchivePalette.inkSecondary)
        }
    }

    // MARK: - 1. 后端中枢地址与连通性探针

    private var hubConnectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("01 · 数据中枢连接地址")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 10) {
                TextField("http://localhost:8088", text: $appState.hubURLString)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: 13))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                    .padding(9)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                    )

                Button("保存并探测中枢") {
                    APIClient.shared.setBaseURL(appState.hubURLString)
                    Task { @MainActor in
                        healthResult = try? await APIClient.shared.checkHealth()
                        await appState.refreshAll(forceFull: true)
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            if let health = healthResult {
                HStack(spacing: 8) {
                    Circle()
                        .fill(ArchivePalette.accentMoss)
                        .frame(width: 7, height: 7)
                    Text("\(health.service) · 版本 \(health.version ?? "v1.1.0") · R2 存储 \(health.storageR2 == true ? "已就绪" : "本地模式")")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                }
            }
        }
        .padding(16)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 2. 设备免密配对与本机凭据托管

    private var devicePairingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("02 · 设备免密配对与本机凭据")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .frame(width: 7, height: 7)
                    Text(appState.isPaired ? "本机已托管有效设备凭证 (主理人全权管理)" : "尚未配对")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(appState.isPaired ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                }
            }

            if appState.isPaired {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机设备标识：\(CredentialStore.getDeviceId() ?? "dev_macos")")
                            .font(ArchiveTypography.monoScale(size: 12))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("登记名称：\(CredentialStore.getDeviceName() ?? "Mac 工作台") · 凭证档案: credentials.json")
                            .font(ArchiveTypography.monoScale(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    Spacer()
                    Button("解除本机配对") {
                        appState.disconnectDevice()
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
                .padding(12)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                HStack(spacing: 6) {
                    ForEach(PairingMethod.allCases, id: \.rawValue) { method in
                        PaperPillButton(
                            title: method.rawValue,
                            isSelected: selectedMethod == method
                        ) {
                            selectedMethod = method
                            authError = nil
                            AudioFeedback.shared.playTink()
                        }
                    }
                }

                switch selectedMethod {
                case .passcode:
                    HStack(spacing: 10) {
                        SecureField("输入主理人管理员密钥（直接签发本机专属子钥匙）", text: $passcodeInput)
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.monoScale(size: 13))
                            .padding(9)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                            )

                        Button(isSubmittingAuth ? "验证中…" : "验证并绑定本机") {
                            performPasscodeVerify()
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                        .disabled(passcodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingAuth)
                    }

                case .ticketURI:
                    HStack(spacing: 10) {
                        TextField("粘贴配对链接 looseleaf://pair?hub=...&ticket=pair_tk_...", text: $ticketURIInput)
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.monoScale(size: 12))
                            .padding(9)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                            )

                        Button(isSubmittingAuth ? "核销中…" : "核销工单配对") {
                            performTicketPairing()
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                        .disabled(ticketURIInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingAuth)
                    }
                }
            }

            if let authFeedback {
                Text(authFeedback)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentMoss)
            }
            if let authError {
                Text(authError)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }
        }
        .padding(16)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 3. 受信任设备组管理

    private var trustedDevicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("03 · 受信任设备组 (\(appState.trustedDevices.count))")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                Button("签发新设备 6 位配对码") {
                    Task { @MainActor in
                        issuedPairTicket = try? await APIClient.shared.initPairing()
                        AudioFeedback.shared.playPaperFlip()
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            if let ticket = issuedPairTicket {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("临时 6 位配对码（5 分钟内有效）")
                            .font(ArchiveTypography.bodySans(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                        Text(ticket.pinCode)
                            .font(ArchiveTypography.monoScale(size: 22, weight: .bold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text(ticket.qrPayload)
                            .font(ArchiveTypography.monoScale(size: 10))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(12)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            ForEach(appState.trustedDevices) { dev in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(dev.name)
                                .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            Text(dev.platform)
                                .font(ArchiveTypography.monoScale(size: 10))
                                .foregroundStyle(ArchivePalette.accentMoss)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text("\(dev.deviceId) · 最近活跃 \(FormatUtils.parseOccurredDate(dev.lastActiveAt).dotDateTime)")
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }
                    Spacer()
                    if dev.deviceId != CredentialStore.getDeviceId() {
                        Button("吊销") {
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
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .buttonStyle(.plain)
                    } else {
                        Text("当前设备")
                            .font(ArchiveTypography.monoScale(size: 10.5))
                            .foregroundStyle(ArchivePalette.accentMoss)
                    }
                }
                .padding(10)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(16)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 4. 视觉与声学触觉偏好

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("04 · 纸本视觉、拟物声学与全局快捷键")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack {
                Text("纸本与暗房外观")
                    .font(ArchiveTypography.bodySans(size: 12.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(AppearanceMode.allCases) { mode in
                        PaperPillButton(
                            title: mode.label,
                            isSelected: appState.appearanceMode == mode
                        ) {
                            appState.appearanceMode = mode
                            AudioFeedback.shared.playTink()
                        }
                    }
                }
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("机械相机快门与翻纸音效")
                        .font(ArchiveTypography.bodySans(size: 12.5))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("提交闪念、记账或显影完成时播放 32ms 无损快门闭合声")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                Button("试听快门") {
                    AudioFeedback.shared.playShutter()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                Toggle("", isOn: $appState.soundEnabled)
                    .labelsHidden()
                    .tint(ArchivePalette.accentWarm)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("触控板物理触觉反馈 (Force Touch Haptics)")
                        .font(ArchiveTypography.bodySans(size: 12.5))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("通过 NSHapticFeedbackManager 提供图章落纸般的物理微震感")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()
                Toggle("", isOn: $appState.hapticsEnabled)
                    .labelsHidden()
                    .tint(ArchivePalette.accentWarm)
            }

            Divider().overlay(ArchivePalette.borderSubtle)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("全局呼出极速闪念悬浮窗热键")
                        .font(ArchiveTypography.bodySans(size: 12.5))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Text("点击「修改」后按下新的组合键（须包含 ⌘ / ⌥ / ⌃ 之一）")
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                Spacer()

                if isRecordingHotKey {
                    Text("请按下组合键…")
                        .font(ArchiveTypography.monoScale(size: 12, weight: .semibold))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ArchivePalette.accentWarm, lineWidth: 0.5)
                        )

                    HotKeyRecorderView(isRecording: $isRecordingHotKey) { keyCode, modifiers in
                        (NSApp.delegate as? AppDelegate)?.applyHotKey(keyCode: keyCode, carbonModifiers: modifiers)
                        hotKeyLabel = AppDelegate.hotKeyDisplayName
                        isRecordingHotKey = false
                        AudioFeedback.shared.playTink()
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                } else {
                    Text(hotKeyLabel)
                        .font(ArchiveTypography.monoScale(size: 12, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                        )

                    Button("修改") {
                        isRecordingHotKey = true
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                    if hotKeyLabel != AppDelegate.displayString(keyCode: Int(kVK_ANSI_L), carbonModifiers: Int(cmdKey | shiftKey)) {
                        Button("重置") {
                            (NSApp.delegate as? AppDelegate)?.applyHotKey(
                                keyCode: Int(kVK_ANSI_L),
                                carbonModifiers: Int(cmdKey | shiftKey)
                            )
                            hotKeyLabel = AppDelegate.hotKeyDisplayName
                        }
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    }
                }
            }
        }
        .padding(16)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 5. 离线发件箱与本地缓存

    private var localSyncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("05 · 本地优先缓存与离线发件箱 (Outbox)")
                    .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                Button("立即全量同步") {
                    Task { @MainActor in
                        await appState.refreshAll(forceFull: true)
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            HStack(spacing: 20) {
                Text("本地缓存散页：\(appState.entries.count) 篇")
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Text("本地缓存账单：\(appState.transactions.count) 笔")
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Text("待同步发件箱：\(appState.outboxItems.count) 项")
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(appState.outboxItems.isEmpty ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
            }
        }
        .padding(16)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 配对动作执行

    private func performPasscodeVerify() {
        isSubmittingAuth = true
        authError = nil
        authFeedback = nil
        Task { @MainActor in
            do {
                try await appState.verifyWithMasterPasscode(passcodeInput, hubURL: appState.hubURLString)
                passcodeInput = ""
                authFeedback = "验证通过！本机设备凭证已更新。"
                await refreshDevicesList()
            } catch {
                authError = error.localizedDescription
            }
            isSubmittingAuth = false
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
                    // 完整深链：统一解析器取 hub + ticket（未注册 scheme 的环境下粘贴同样生效）
                    guard let parsed = AppState.parsePairLink(raw) else {
                        authError = "无法识别配对链接，请在网页后台点击「复制配对链接」后重试"
                        isSubmittingAuth = false
                        return
                    }
                    let hub = parsed.hub.isEmpty ? appState.hubURLString : parsed.hub
                    try await appState.pairWithTicket(parsed.ticket, hubURL: hub)
                } else {
                    // 纯工单号：地址沿用当前中枢
                    try await appState.pairWithTicket(raw, hubURL: appState.hubURLString)
                }
                ticketURIInput = ""
                authFeedback = "配对成功！设备令牌已写入本机受保护档案。"
                await refreshDevicesList()
            } catch {
                authError = error.localizedDescription
            }
            isSubmittingAuth = false
        }
    }

    private func refreshDevicesList() async {
        isLoadingDevices = true
        if let list = try? await APIClient.shared.fetchTrustedDevices() {
            appState.trustedDevices = list
        }
        isLoadingDevices = false
    }
}

// MARK: - 全局热键录制控件 (HotKeyRecorder)

/// 捕获一次组合键（须包含修饰键；Esc 取消）并回传 Carbon 键位与修饰键值
struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCaptured: (Int, Int) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onCaptured = onCaptured
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.onCaptured = onCaptured
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class RecorderNSView: NSView {
    var onCaptured: ((Int, Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            return // Esc 取消录制
        }
        var carbonModifiers: Int = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { carbonModifiers |= Int(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= Int(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= Int(shiftKey) }
        if flags.contains(.control) { carbonModifiers |= Int(controlKey) }
        guard carbonModifiers != 0 else { return } // 必须包含修饰键，避免误吞裸键
        onCaptured?(Int(event.keyCode), carbonModifiers)
    }
}
