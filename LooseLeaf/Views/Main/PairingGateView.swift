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

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack {
            NoiseBackground(useSubtleSurface: false, enableVibrancy: true)

            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 12)

                    // 1. 散页标志性刊头
                    VStack(spacing: 8) {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(ArchivePalette.accentWarm)

                        Text("散页 · Loose-Leaf")
                            .font(ArchiveTypography.editorialSerif(size: 24, weight: .bold))
                            .foregroundStyle(ArchivePalette.inkPrimary)

                        Text("主理人专属数字档案馆与桌面暗房工作台")
                            .font(ArchiveTypography.bodySans(size: 12.5))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }

                    // 2. 中枢连接状态胶囊
                    hubStatusPill

                    // 3. 核心认证卡片
                    VStack(spacing: 16) {
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
                    .padding(20)
                    .frame(maxWidth: 440)
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
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
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
            HStack(spacing: 6) {
                Circle()
                    .fill(isProbing ? ArchivePalette.inkMuted : (probeError == nil ? ArchivePalette.accentMoss : ArchivePalette.accentWarm))
                    .frame(width: 7, height: 7)

                Text(appState.hubURLString)
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkSecondary)

                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(ArchivePalette.archivePaper)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var probingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("正在探测数据中枢连通性…")
                .font(ArchiveTypography.bodySans(size: 12))
                .foregroundStyle(ArchivePalette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func connectionFailedView(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28))
                .foregroundStyle(ArchivePalette.accentWarm)

            Text("无法连接至数据中枢")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text(error)
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

    // MARK: - 未初始化提示 (引导去 Web 展厅)

    private var uninitializedGuideView: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(ArchivePalette.accentWarm)

            Text("中枢尚未完成创刊装帧")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text("《散页》遵循「Web 展厅向导装帧」原则。请先在浏览器中访问 Web 展厅设定管理员主密钥与站点基本信息；装帧完成后，在 Web 端「设备管理」生成配对二维码或链接，即可无缝接入本桌面端。")
                .font(ArchiveTypography.bodySans(size: 12))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 10) {
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
        .padding(.vertical, 8)
    }

    // MARK: - 已装帧状态：配对工单与链接配对

    private var pairedTicketView: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("受信任设备配对")
                    .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("在 Web 展厅后台「设备管理」点击「复制配对链接」，粘贴至此即可完成免密配对。")
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("looseleaf://pair?hub=…&ticket=… 或配对工单 Ticket", text: $pairLinkInput)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 11.5))
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                )
                .onSubmit {
                    performPairLinkPairing()
                }

            HStack(spacing: 8) {
                Button {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        pairLinkInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Text("读取剪贴板")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                Button {
                    performPairLinkPairing()
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
                .keyboardShortcut(.defaultAction)
                .disabled(pairLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
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
                AudioFeedback.shared.playShutter()
                isSubmitting = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    // MARK: - 中枢地址配置弹窗

    private var hubConfigSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置数据中枢 Hub 地址")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("http://localhost:8088", text: $appState.hubURLString)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.monoScale(size: 13))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Spacer()
                Button("完成并重新探测") {
                    showHubConfig = false
                    Task { @MainActor in
                        await probeHub()
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(ArchivePalette.archivePaper)
    }
}
