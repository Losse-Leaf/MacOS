import SwiftUI
import AppKit

/// 散页账号登录门禁 (OAuth 2.0 / OIDC · Vesper Auth)
/// 点击「使用 Vesper Auth 登录」在系统浏览器完成身份验证，认证后自动回跳应用进入工作台。
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

    // Vesper Auth OAuth2 登录状态
    @State private var hasOpenedBrowserForSSO: Bool = false
    @State private var errorMessage: String?
    /// 服务器地址弹窗内的校验错误（就地渲染，避免被弹窗遮挡）
    @State private var hubConfigError: String?
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
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.heroIcon))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .accessibilityHidden(true)

                        Text("散页 · Loose-Leaf")
                            .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.display, weight: .bold))
                            .foregroundStyle(ArchivePalette.inkPrimary)

                        Text("登录你的 Vesper Auth 账号，同步散页、心愿与账本")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }

                    // 2. 服务器地址胶囊（可按需修改自托管地址）
                    hubStatusPill

                    // 3. 核心 OAuth2 登录卡片
                    VStack(spacing: ArchiveSpacing.l) {
                        if isProbing {
                            probingView
                        } else if let err = probeError {
                            connectionFailedView(error: err)
                        } else if systemStatus?.oidcEnabled == false {
                            oidcDisabledView
                        } else {
                            vesperAuthPrimaryView
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

                    // 登录失败原因统一以反馈条呈现
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
                    .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.micro))
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
        .accessibilityLabel("配置服务器地址，当前为 \(appState.hubURLString)")
        .help("点击修改同步服务器地址")
    }

    private var probingView: some View {
        VStack(spacing: ArchiveSpacing.m) {
            ProgressView()
                .controlSize(.regular)
            Text("正在连接服务器…")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ArchiveSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在连接服务器")
    }

    private func connectionFailedView(error: String) -> some View {
        VStack(spacing: ArchiveSpacing.m) {
            Image(systemName: "wifi.slash")
                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.emptyIcon))
                .foregroundStyle(ArchivePalette.accentWarm)

            Text("无法连接至服务器")
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

    private var oidcDisabledView: some View {
        VStack(spacing: ArchiveSpacing.m) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.emptyIcon))
                .foregroundStyle(ArchivePalette.accentWarm)
                .accessibilityHidden(true)

            Text("服务器未启用 OAuth 2.0 登录")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text("请在服务端启用 Vesper Auth (OIDC) 配置，或点击上方地址胶囊切换至已启用登录的服务器。")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button("重新检测") {
                Task { @MainActor in
                    await probeHub()
                }
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            .paperButtonFocusRing()
        }
        .padding(.vertical, ArchiveSpacing.s)
    }

    // MARK: - Vesper Auth 账号登录主通道

    private var vesperAuthPrimaryView: some View {
        let providerName = {
            let trimmed = (systemStatus?.oidcProviderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Vesper Auth" : trimmed
        }()
        let isBusy = appState.isConfirmingIncomingPairTicket

        return VStack(spacing: ArchiveSpacing.m) {
            VStack(spacing: ArchiveSpacing.xs) {
                Text("账号登录")
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                Text("将在系统浏览器中跳转至 \(providerName) 完成登录，验证通过后自动返回《散页》。")
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
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "person.badge.key.fill")
                            .font(ArchiveTypography.icon(size: ArchiveTypography.Scale.heading))
                            .accessibilityHidden(true)
                    }
                    Text(isBusy
                         ? "正在验证身份并建立登录会话…"
                         : "使用 \(providerName) 登录")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            .paperButtonFocusRing()
            .keyboardShortcut(.defaultAction)
            .disabled(isBusy)
            .accessibilityHint("打开默认浏览器完成 Vesper Auth 账号登录并自动返回应用")

            if hasOpenedBrowserForSSO && !isBusy {
                Text("已在默认浏览器中打开 \(providerName) 登录页，认证通过后会自动返回《散页》。")
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
            errorMessage = "当前服务器地址格式无效，请先点击上方胶囊核对地址"
            return
        }
        if NSWorkspace.shared.open(loginURL) {
            hasOpenedBrowserForSSO = true
        } else {
            errorMessage = "无法唤起系统默认浏览器，请检查系统默认浏览器设置后重试"
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

    // MARK: - 服务器地址配置弹窗

    private var hubConfigSheet: some View {
        PaperSheetScaffold(
            title: "配置同步服务器地址",
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
                    .accessibilityLabel("服务器地址")
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

    private func applyHubConfig() {
        let trimmed = draftHubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            hubConfigError = "服务器地址格式无效，请填写 http:// 或 https:// 开头的完整地址"
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
