import SwiftUI
import AppKit

/// 主理人工作台激活与配对门禁 (PairingGateView)
/// 严格遵循：macOS 桌面端彻底废除访客只读模式；
/// 未配对时全屏拦截，支持「首次装帧设密」或「管理员密钥一键直登」/「6位配对码」，配对后即为全权管理级别。
@MainActor
public struct PairingGateView: View {
    @Bindable var appState: AppState

    public enum Mode: String, CaseIterable {
        case masterPasscode = "管理员密钥登录"
        case pinCode = "6 位数字配对码"
    }

    @State private var mode: Mode = .masterPasscode

    // 状态探针
    @State private var isProbing: Bool = true
    @State private var systemStatus: SystemStatus?
    @State private var probeError: String?
    @State private var showHubConfig: Bool = false

    // 首次装帧表单
    @State private var bootstrapName: String = "主理人"
    @State private var bootstrapLocation: String = ""
    @State private var bootstrapPasscode: String = ""
    @State private var bootstrapConfirm: String = ""

    // 密钥登录表单
    @State private var passcodeInput: String = ""

    // 6 位配对码表单
    @State private var pinDigits: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedPinIndex: Int?

    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    public init(appState: AppState) {
        self.appState = appState
    }

    private var pinCodeString: String {
        pinDigits.joined()
    }

    public var body: some View {
        ZStack {
            NoiseBackground(useSubtleSurface: false, enableVibrancy: true)

            VStack(spacing: 24) {
                Spacer(minLength: 20)

                // 1. 散页标志性刊头
                VStack(spacing: 8) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(ArchivePalette.accentWarm)

                    Text("散页 · Loose-Leaf")
                        .font(ArchiveTypography.editorialSerif(size: 26, weight: .bold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Text("主理人专属数字档案馆与桌面暗房工作台")
                        .font(ArchiveTypography.bodySans(size: 13))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                }

                // 2. 中枢连接状态胶囊
                hubStatusPill

                // 3. 核心认证卡片
                VStack(spacing: 18) {
                    if isProbing {
                        probingView
                    } else if let err = probeError {
                        connectionFailedView(error: err)
                    } else if systemStatus?.initialized == false {
                        bootstrapGuideView
                    } else {
                        pairedLoginView
                    }
                }
                .padding(24)
                .frame(width: 440)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)

                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text(error)
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(Capsule())
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .task {
            await probeHub()
        }
    }

    // MARK: - 中枢状态条

    private var hubStatusPill: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showHubConfig.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(probeError == nil ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .frame(width: 7, height: 7)
                    Text("数据中枢：\(appState.hubURLString)")
                        .font(ArchiveTypography.monoScale(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    Image(systemName: showHubConfig ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if showHubConfig {
                HStack(spacing: 8) {
                    TextField("http://127.0.0.1:8088", text: $appState.hubURLString)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 12))
                        .padding(7)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                        )
                        .frame(width: 240)

                    Button("重新连接") {
                        APIClient.shared.setBaseURL(appState.hubURLString)
                        Task { @MainActor in
                            await probeHub()
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - 探针中视图

    private var probingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("正在探测本地散页中枢生命周期…")
                .font(ArchiveTypography.bodySans(size: 12.5))
                .foregroundStyle(ArchivePalette.inkMuted)
        }
        .padding(.vertical, 24)
    }

    private func connectionFailedView(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(ArchivePalette.accentWarm)

            Text("无法连接到后端数据中枢")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text(error)
                .font(ArchiveTypography.bodySans(size: 12))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .multilineTextAlignment(.center)

            Text("请确认 backend 已启动（默认端口 8088）：\ncd backend && go run main.go")
                .font(ArchiveTypography.monoScale(size: 11))
                .foregroundStyle(ArchivePalette.inkMuted)
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Button("再次尝试连接") {
                Task { @MainActor in
                    await probeHub()
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .padding(.top, 4)
        }
    }

    // MARK: - 首次装帧向导 (Bootstrap Guide)

    private var bootstrapGuideView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("初次装帧 · 设定管理员密钥")
                    .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("检测到当前为全新部署。无需打开网页，直接在此设定密钥即可完成自留地装帧并激活本机工作台。")
                    .font(ArchiveTypography.bodySans(size: 12))
                    .foregroundStyle(ArchivePalette.inkSecondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("主理人称谓")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("如：主理人、星河", text: $bootstrapName)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("常驻城市")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                TextField("如：杭州、大理", text: $bootstrapLocation)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("管理员主密钥 (Master Passcode)")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                SecureField("设定您的专属管理密钥", text: $bootstrapPasscode)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("确认管理员主密钥")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                SecureField("再次输入一致的密钥", text: $bootstrapConfirm)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Button {
                performBootstrap()
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    }
                    Text("完成装帧并进入工作台 (⌘↩)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(bootstrapPasscode.isEmpty || bootstrapPasscode != bootstrapConfirm || isSubmitting)
            .padding(.top, 4)
        }
    }

    // MARK: - 已装帧状态：主理人密钥登录 / 6 位配对码

    private var pairedLoginView: some View {
        VStack(spacing: 16) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .masterPasscode {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("主理人管理员密钥")
                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("输入您在装帧时设定的密钥，验证通过后自动为本机签发受信任设备子钥匙并写入钥匙串。")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    SecureField("输入主理人密钥…", text: $passcodeInput)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 14))
                        .padding(10)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                        )
                        .onSubmit {
                            performPasscodeLogin()
                        }

                    Button {
                        performPasscodeLogin()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().controlSize(.small)
                            }
                            Text("验证并进入工作台 ↩")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(passcodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            } else {
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text("输入 6 位配对码")
                            .font(ArchiveTypography.bodySans(size: 13, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("在已登录的网页后台或手机端生成 6 位配对码，输入即可完成免密授信绑定。")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { idx in
                            TextField("", text: $pinDigits[idx])
                                .multilineTextAlignment(.center)
                                .font(ArchiveTypography.monoScale(size: 20, weight: .bold))
                                .frame(width: 44, height: 48)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(focusedPinIndex == idx ? ArchivePalette.accentWarm : ArchivePalette.borderDivider, lineWidth: 1)
                                )
                                .focused($focusedPinIndex, equals: idx)
                                .onChange(of: pinDigits[idx]) { _, newValue in
                                    handlePinDigitChange(at: idx, newValue: newValue)
                                }
                        }
                    }
                    .padding(.vertical, 6)

                    Button {
                        performPinPairing()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().controlSize(.small)
                            }
                            Text("确认配对 ↩")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    .disabled(pinCodeString.count < 6 || isSubmitting)
                }
            }
        }
    }

    // MARK: - 业务动作

    private func probeHub() async {
        isProbing = true
        probeError = nil
        errorMessage = nil
        do {
            let status = try await APIClient.shared.fetchSystemStatus()
            systemStatus = status
            isProbing = false
        } catch {
            probeError = error.localizedDescription
            isProbing = false
        }
    }

    private func performBootstrap() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let req = BootstrapRequest(
                    curatorName: bootstrapName.trimmingCharacters(in: .whitespacesAndNewlines),
                    location: bootstrapLocation.trimmingCharacters(in: .whitespacesAndNewlines),
                    masterPasscode: bootstrapPasscode,
                    confirmPasscode: bootstrapConfirm,
                    hubUrl: appState.hubURLString
                )
                let ticketResp = try await APIClient.shared.bootstrapSystem(req)
                // 首次装帧成功后立即使用返回的 ticket 完成握手，一步直接进入！
                try await appState.pairWithTicket(ticketResp.ticket, hubURL: appState.hubURLString)
                AudioFeedback.shared.playShutter()
                isSubmitting = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func performPasscodeLogin() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await appState.verifyWithMasterPasscode(passcodeInput, hubURL: appState.hubURLString)
                AudioFeedback.shared.playShutter()
                isSubmitting = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func performPinPairing() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await appState.pairWithPinCode(pinCodeString, hubURL: appState.hubURLString)
                AudioFeedback.shared.playShutter()
                isSubmitting = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func handlePinDigitChange(at index: Int, newValue: String) {
        if newValue.count > 1 {
            // 支持一次性粘贴 6 位数字
            let filtered = newValue.filter { $0.isNumber }
            if filtered.count == 6 {
                let chars = Array(filtered)
                for i in 0..<6 {
                    pinDigits[i] = String(chars[i])
                }
                focusedPinIndex = nil
                performPinPairing()
                return
            } else {
                pinDigits[index] = String(newValue.prefix(1))
            }
        }

        if !newValue.isEmpty {
            if index < 5 {
                focusedPinIndex = index + 1
            } else {
                focusedPinIndex = nil
                if pinCodeString.count == 6 {
                    performPinPairing()
                }
            }
        }
    }
}
