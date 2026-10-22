import SwiftUI
import AppKit

/// 主理人工作台激活与配对门禁 (PairingGateView)
/// 严格遵循主理人规范：
/// 1. 桌面端移除首次装帧向导与管理员主密钥登录通道（主密钥仅限 Web 管理后台使用）；
/// 2. 仅支持通过二维码或配对工单链接 (looseleaf://pair?ticket=...) 免密配对接入；
/// 3. 若中枢尚未装帧，友好引导至浏览器 Web 端完成首次创刊。
@MainActor
public struct PairingGateView: View {
    @Bindable var appState: AppState

    // 状态探针
    @State private var isProbing: Bool = true
    @State private var systemStatus: SystemStatus?
    @State private var probeError: String?
    @State private var showHubConfig: Bool = false

    // 配对链接 / 工单输入
    @State private var pairLinkInput: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    /// 中枢地址弹窗内的校验错误（就地渲染，避免被弹窗遮挡）
    @State private var hubConfigError: String?

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

                    // 3. 核心认证卡片
                    VStack(spacing: ArchiveSpacing.l) {
                        if isProbing {
                            probingView
                        } else if let err = probeError {
                            connectionFailedView(error: err)
                        } else if systemStatus?.initialized == false {
                            uninitializedGuideView
                        } else {
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
                    settingsFeedbackBanner(feedback: nil, error: errorMessage)
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
            .padding(.top, 4)
        }
    }

    // MARK: - 未初始化提示 (引导去 Web 展厅)

    private var uninitializedGuideView: some View {
        VStack(spacing: ArchiveSpacing.m) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(ArchivePalette.accentWarm)

            Text("中枢尚未完成创刊装帧")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text("请先在 Web 展厅设定管理员密钥并完成装帧。随后在「设备管理」生成配对二维码或链接即可接入本桌面端。")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: ArchiveSpacing.s) {
                if let url = URL(string: appState.hubURLString) {
                    Link(destination: url) {
                        Text("在浏览器中打开 Web 展厅 ↗")
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                }

                Button("重新检测状态") {
                    Task { @MainActor in
                        await probeHub()
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
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
                Text("粘贴 Web 展厅后台生成的配对链接或工单：")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("looseleaf://pair?hub=…&ticket=… 或配对工单 Ticket", text: $pairLinkInput)
                .accessibilityLabel("配对工单或深链")
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                        .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                )
                .accessibilityLabel("配对链接或工单输入框")
                .disabled(isSubmitting)
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
                // 配对请求进行中禁用全部交互
                .disabled(isSubmitting)

                Button {
                    performPairLinkPairing()
                } label: {
                    HStack(spacing: ArchiveSpacing.xs) {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        }
                        Text(isSubmitting ? "正在配对…" : "确认配对 ↩")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(pairLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .accessibilityHint(isSubmitting ? "正在与中枢握手，请稍候" : "使用填写的链接或工单完成配对")
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

    /// 中枢地址配置弹窗：统一 Sheet 骨架，校验错误就地渲染
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
                TextField("http://localhost:8088", text: $appState.hubURLString)
                    .accessibilityLabel("中枢地址")
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.heading))
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    .accessibilityLabel("数据中枢地址")

                settingsFeedbackBanner(feedback: nil, error: hubConfigError)
            }
        }
    }

    /// 校验并落盘新的中枢地址
    private func applyHubConfig() {
        let trimmed = appState.hubURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            hubConfigError = "中枢地址格式无效，请填写 http:// 或 https:// 开头的完整地址"
            errorMessage = hubConfigError
            return
        }
        // 必须真正落盘：此前只改了内存字段，"重新探测"仍然打旧地址
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
