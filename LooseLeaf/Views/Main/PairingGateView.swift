import SwiftUI
import AppKit

/// 主理人工作台激活与配对门禁 (PairingGateView)
/// 鉴权路径规范：
/// 1. 当中枢启用 Vesper Auth (OIDC) 时，主操作通过系统浏览器完成通行证验证并经由 looseleaf://pair 深链自动握手激活；
/// 2. 兼容局域网免密配对工单链接 (looseleaf://pair?ticket=...) 作为折叠兜底或纯离线模式主通道；
/// 3. 若纯局域网中枢尚未完成创刊，引导至浏览器 Web 端完成首次认领。
@MainActor
public struct PairingGateView: View {
    @Bindable var appState: AppState

    // 状态探针
    @State private var isProbing: Bool = true
    @State private var systemStatus: SystemStatus?
    @State private var probeError: String?
    @State private var showHubConfig: Bool = false
    /// 地址配置弹窗内的局部草稿（点击取消时不污染 `appState.hubURLString`）
    @State private var draftHubURL: String = ""

    // Vesper Auth SSO 与手动兜底状态
    @State private var hasOpenedBrowserForSSO: Bool = false
    @State private var showManualTicketFallback: Bool = false

    // 配对链接 / 工单输入
    @State private var pairLinkInput: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    /// 中枢地址弹窗内的校验错误（就地渲染，避免被弹窗遮挡）
    @State private var hubConfigError: String?
    @FocusState private var isTicketFocused: Bool
    @FocusState private var isHubFieldFocused: Bool

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack {
            NoiseBackground(useSubtleSurface: false, enableVibrancy: true)

            ScrollView {
                VStack(spacing: ArchiveSpacing.xl) {
                    Spacer(minLength: ArchiveSpacing.m)

                    // 1. 散页标志性刊头
                    VStack(spacing: ArchiveSpacing.s) {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .accessibilityHidden(true)

                        Text("散页 · Loose-Leaf")
                            .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.display, weight: .bold))
                            .foregroundStyle(ArchivePalette.inkPrimary)

                        Text("主理人专属数字档案馆与桌面影像工作台")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }

                    // 2. 中枢连接状态胶囊
                    hubStatusPill

                    // 3. 核心认证卡片（支持 Vesper Auth 一键接入与配对深链兜底）
                    VStack(spacing: ArchiveSpacing.l) {
                        if isProbing {
                            probingView
                        } else if systemStatus?.oidcEnabled == true {
                            vesperAuthPrimaryView
                            Divider().overlay(ArchivePalette.borderSubtle)
                            manualTicketFallbackSection
                        } else if systemStatus?.initialized == false {
                            uninitializedGuideView
                        } else {
                            if let err = probeError {
                                connectionFailedView(error: err)
                                Divider().overlay(ArchivePalette.borderSubtle)
                            }
                            pairedTicketView
                        }
                    }
                    .padding(ArchiveSpacing.xl)
                    .frame(maxWidth: ArchiveSheetWidth.compact)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveCardMetrics.radius))
                    .overlay(
                        RoundedRectangle(cornerRadius: ArchiveCardMetrics.radius)
                            .stroke(ArchivePalette.borderSubtle, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)

                    // 配对失败原因统一以反馈条呈现
                    settingsFeedbackBanner(feedback: nil, error: errorMessage ?? appState.errorBanner)
                        .frame(maxWidth: ArchiveSheetWidth.compact)

                    Spacer(minLength: ArchiveSpacing.xl)
                }
                .padding(.horizontal, ArchiveSpacing.xl)
            }
        }
        .task {
            await probeHub()
        }
        .sheet(isPresented: $showHubConfig) {
            hubConfigSheet
        }
    }

    // MARK: - 子视图

    private var hubStatusPill: some View {
        Button {
            draftHubURL = appState.hubURLString
            hubConfigError = nil
            showHubConfig = true
        } label: {
            HStack(spacing: ArchiveSpacing.s) {
                Circle()
                    .fill(isProbing ? ArchivePalette.inkMuted : (probeError == nil ? ArchivePalette.accentMoss : ArchivePalette.accentWarm))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(appState.hubURLString)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkSecondary)

                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, ArchiveSpacing.s)
            .padding(.vertical, ArchiveSpacing.xs)
            .background(ArchivePalette.archivePaper)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .paperButtonFocusRing(cornerRadius: 14)
        .accessibilityLabel("配置数据中枢地址，当前为 \(appState.hubURLString)")
        .help("点击修改数据中枢地址")
    }

    private var probingView: some View {
        VStack(spacing: ArchiveSpacing.m) {
            ProgressView()
                .controlSize(.regular)
            Text("正在探测数据中枢连通性…")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ArchiveSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在探测数据中枢连通性")
    }

    private func connectionFailedView(error: String) -> some View {
        VStack(spacing: ArchiveSpacing.m) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28))
                .foregroundStyle(ArchivePalette.accentWarm)

            Text("无法连接至数据中枢")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text(error)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(ArchivePalette.inkMuted)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            Button("再次尝试连接") {
                Task { @MainActor in
                    await probeHub()
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
            .padding(.top, 4)
        }
    }

    // MARK: - Vesper Auth 统一通行证主通道

    private var vesperAuthPrimaryView: some View {
        let providerName = {
            let trimmed = (systemStatus?.oidcProviderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Vesper Auth" : trimmed
        }()
        let isBusy = isSubmitting || appState.isConfirmingIncomingPairTicket

        return VStack(spacing: ArchiveSpacing.m) {
            VStack(spacing: ArchiveSpacing.xs) {
                Text(systemStatus?.initialized == false ? "创刊装帧与桌面端接入" : "主理人通行证接入")
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Text("在系统浏览器中通过 \(providerName) 验证通行密钥后，将自动唤起《散页》签发本机受信任凭证。")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                openVesperAuthInBrowser()
            } label: {
                HStack(spacing: ArchiveSpacing.xs) {
                    if appState.isConfirmingIncomingPairTicket {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 13))
                            .accessibilityHidden(true)
                    }
                    Text(appState.isConfirmingIncomingPairTicket
                         ? "正在核销通行证回跳工单…"
                         : "通过 Vesper Auth 通行证一键接入")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
            .keyboardShortcut(.defaultAction)
            .disabled(isBusy)
            .accessibilityHint("打开默认浏览器完成 Vesper Auth 认证并自动回跳激活本机")

            if hasOpenedBrowserForSSO && !appState.isConfirmingIncomingPairTicket {
                Text("已在默认浏览器打开认证页。验证通过后会自动跳回《散页》；若浏览器拦截了深链唤起，可展开下方兜底入口粘贴一次性授权深链。")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(ArchiveSpacing.s)
                    .frame(maxWidth: .infinity)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
            }
        }
    }

    private var manualTicketFallbackSection: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showManualTicketFallback.toggle()
                }
                if showManualTicketFallback {
                    isTicketFocused = true
                }
            } label: {
                HStack(spacing: ArchiveSpacing.xs) {
                    Image(systemName: showManualTicketFallback ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkMuted)
                        .frame(width: 12)
                        .accessibilityHidden(true)

                    Text("手动粘贴配对深链或工单（局域网 / 备用兜底）")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkSecondary)

                    Spacer()
                }
                .padding(.vertical, ArchiveSpacing.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
            .accessibilityLabel("手动粘贴配对深链或工单")
            .accessibilityValue(showManualTicketFallback ? "已展开" : "已折叠")

            if showManualTicketFallback {
                pairedTicketInputControls(includeDefaultShortcut: false)
            }
        }
    }

    // MARK: - 未初始化提示 (纯局域网无 OIDC 时引导去 Web 展厅)

    private var uninitializedGuideView: some View {
        VStack(spacing: ArchiveSpacing.m) {
            Image(systemName: "book.closed")
                .font(.system(size: 30))
                .foregroundStyle(ArchivePalette.accentWarm)
                .accessibilityHidden(true)

            Text("中枢尚未完成创刊装帧")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text("请先在 Web 页面输入服务启动时打印的认领码完成首次认领。随后在「设备管理」生成配对二维码或链接即可接入本桌面端。")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: ArchiveSpacing.s) {
                if let url = URL(string: appState.hubURLString) {
                    Link(destination: url) {
                        Text("在浏览器中打开 Web 展厅")
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    .paperButtonFocusRing()
                }

                Button("重新检测状态") {
                    Task { @MainActor in
                        await probeHub()
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
            }
            .padding(.top, 6)
        }
        .padding(.vertical, ArchiveSpacing.s)
    }

    // MARK: - 已装帧状态：配对工单与链接配对

    private var pairedTicketView: some View {
        VStack(spacing: ArchiveSpacing.m) {
            VStack(spacing: ArchiveSpacing.xs) {
                Text("受信任设备配对")
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("粘贴 Web 展厅后台或授权中转页生成的配对链接或工单：")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            pairedTicketInputControls(includeDefaultShortcut: true)
        }
    }

    private func pairedTicketInputControls(includeDefaultShortcut: Bool) -> some View {
        let isBusy = isSubmitting || appState.isConfirmingIncomingPairTicket

        return VStack(spacing: ArchiveSpacing.m) {
            TextField("looseleaf://pair?hub=…&ticket=… 或配对工单 Ticket", text: $pairLinkInput)
                .accessibilityLabel("配对工单或深链输入框")
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                .focused($isTicketFocused)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                )
                .disabled(isBusy)
                .onSubmit {
                    performPairLinkPairing()
                }

            HStack(spacing: ArchiveSpacing.s) {
                Button {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        pairLinkInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Text("读取剪贴板")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
                .disabled(isBusy)

                if includeDefaultShortcut {
                    confirmPairButton(isBusy: isBusy)
                        .keyboardShortcut(.defaultAction)
                } else {
                    confirmPairButton(isBusy: isBusy)
                }
            }
        }
    }

    private func confirmPairButton(isBusy: Bool) -> some View {
        Button {
            performPairLinkPairing()
        } label: {
            HStack(spacing: ArchiveSpacing.xs) {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                }
                Text(isSubmitting ? "正在配对…" : "确认配对")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
        .paperButtonFocusRing()
        .disabled(pairLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
        .accessibilityHint(isSubmitting ? "正在与中枢握手，请稍候" : "使用填写的链接或工单完成配对")
    }

    // MARK: - 业务动作

    private func openVesperAuthInBrowser() {
        errorMessage = nil
        appState.errorBanner = nil
        let hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        guard let loginURL = AppState.buildOIDCLoginURL(
            hubURL: appState.hubURLString,
            platform: "macos",
            deviceName: hostName
        ) else {
            errorMessage = "当前数据中枢地址格式无效，请先点击上方胶囊核对 Hub 地址"
            return
        }
        if NSWorkspace.shared.open(loginURL) {
            hasOpenedBrowserForSSO = true
        } else {
            errorMessage = "无法唤起系统默认浏览器，请展开下方手动兜底入口完成配对"
        }
    }

    private func probeHub() async {
        isProbing = true
        probeError = nil
        errorMessage = nil
        appState.errorBanner = nil
        hasOpenedBrowserForSSO = false
        do {
            let status = try await APIClient.shared.fetchSystemStatus()
            systemStatus = status
            isProbing = false
        } catch {
            systemStatus = nil
            probeError = error.localizedDescription
            isProbing = false
        }
    }

    private func performPairLinkPairing() {
        guard !isSubmitting else { return }
        let trimmed = pairLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                if let parsed = AppState.parsePairLink(trimmed) {
                    let hub = parsed.hub.isEmpty ? appState.hubURLString : parsed.hub
                    try await appState.pairWithTicket(parsed.ticket, hubURL: hub)
                } else {
                    // 若直接输入纯 ticket 码 (如 pair_tk_xxx)
                    try await appState.pairWithTicket(trimmed, hubURL: appState.hubURLString)
                }
                isSubmitting = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    // MARK: - 中枢地址配置弹窗

    /// 中枢地址配置弹窗：使用局部草稿状态，点击取消不污染全局地址
    private var hubConfigSheet: some View {
        PaperSheetScaffold(
            title: "配置数据中枢 Hub 地址",
            width: ArchiveSheetWidth.compact,
            submitTitle: "完成并重新探测",
            onCancel: {
                hubConfigError = nil
                showHubConfig = false
            },
            onSubmit: {
                applyHubConfig()
            }
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                TextField("https://leaf.starryheavens.uk", text: $draftHubURL)
                    .accessibilityLabel("数据中枢地址")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                    .focused($isHubFieldFocused)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .onSubmit {
                        applyHubConfig()
                    }

                settingsFeedbackBanner(feedback: nil, error: hubConfigError)
            }
            .onAppear {
                if draftHubURL.isEmpty {
                    draftHubURL = appState.hubURLString
                }
                isHubFieldFocused = true
            }
        }
    }

    /// 校验并落盘新的中枢地址
    private func applyHubConfig() {
        let trimmed = draftHubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            hubConfigError = "中枢地址格式无效，请填写 http:// 或 https:// 开头的完整地址"
            errorMessage = hubConfigError
            return
        }
        APIClient.shared.setBaseURL(trimmed)
        appState.hubURLString = APIClient.shared.baseURLString
        hubConfigError = nil
        errorMessage = nil
        showHubConfig = false
        Task { @MainActor in
            await probeHub()
        }
    }
}
