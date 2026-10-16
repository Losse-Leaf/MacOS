import SwiftUI
import Carbon
import UniformTypeIdentifiers

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

    // 设备重命名状态
    @State private var renamingDevice: TrustedDevice?
    @State private var newDeviceNameInput: String = ""

    // 分类字典管理状态
    @State private var selectedCategoryScope: String = "expense"
    @State private var newCategoryNameInput: String = ""
    @State private var allCategoriesList: [CategoryOption] = []
    @State private var isExportingArchive: Bool = false

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

                // 0. 软件版本与在线更新
                appUpdateCard

                // 1. 后端中枢地址与连通探针
                hubConnectionCard

                // 2. 设备免密配对与本机凭据管理
                devicePairingCard

                // 3. 已授信设备列表与发起移动端配对 (仅已配对时展示)
                if appState.isPaired {
                    trustedDevicesCard
                    categoryManagerCard
                }

                // 4. 视觉模式、拟物声学与触控板反馈设置
                preferencesCard

                // 5. 本地优先缓存与离线发件箱状态
                localSyncCard
            }
            .padding(24)
        }
        .sheet(item: $renamingDevice) { dev in
            renameDeviceSheetView(dev: dev)
        }
        .task {
            if appState.isPaired {
                await refreshDevicesList()
                allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
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

    // MARK: - 0. 软件版本与在线更新

    private var appUpdateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("活页集 Loose-Leaf for Mac")
                        .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text("当前版本 v\(UpdateChecker.shared.currentVersion) · 原生 Apple Silicon (arm64)")
                        .font(ArchiveTypography.monoScale(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Spacer()

                if UpdateChecker.shared.isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("检查新版本") {
                        Task { @MainActor in
                            await UpdateChecker.shared.checkForUpdates(isUserInitiated: true)
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
            }

            if let update = UpdateChecker.shared.availableUpdate {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("🎉 发现新版本 \(update.tagName)")
                            .font(ArchiveTypography.bodySans(size: 12.5, weight: .semibold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text(update.body.isEmpty ? "包含功能更新与稳定性增强。" : update.body)
                            .font(ArchiveTypography.bodySans(size: 11))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    if UpdateChecker.shared.isUpdating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("\(Int(UpdateChecker.shared.updateProgress * 100))%")
                                .font(ArchiveTypography.monoScale(size: 11))
                        }
                    } else {
                        HStack(spacing: 8) {
                            Button("浏览器下载") {
                                UpdateChecker.shared.openDownloadInBrowser()
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                            Button("复制终端命令") {
                                UpdateChecker.shared.copyInstallCommandToClipboard()
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                            Button("应用内更新") {
                                Task { @MainActor in
                                    await UpdateChecker.shared.performInAppUpdate()
                                }
                            }
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                        }
                    }
                }
                .padding(10)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(ArchivePalette.accentWarm.opacity(0.3), lineWidth: 0.8)
                )
            }

            if let err = UpdateChecker.shared.updateError {
                Text(err)
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
                    Text(appState.isPaired ? "本机已安全接入数据中枢" : "尚未接入中枢")
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
                        Text("设备名称：\(CredentialStore.getDeviceName() ?? "Mac 工作台")")
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
                Button {
                    Task { @MainActor in
                        issuedPairTicket = try? await APIClient.shared.initPairing()
                        AudioFeedback.shared.playPaperFlip()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "link.badge.plus")
                        Text("生成新设备配对凭证")
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            if let ticket = issuedPairTicket {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("新设备配对凭证（5 分钟内有效）")
                                .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            Text("使用随行手机扫描纸墨二维码，或复制配对链接在客户端一键接入。")
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }
                        Spacer()
                        Button("收起") {
                            issuedPairTicket = nil
                        }
                        .font(ArchiveTypography.bodySans(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        // 纸墨风格二维码
                        if let qrImg = decodeDataURLImage(ticket.qrCodeDataUrl) {
                            Image(nsImage: qrImg)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 108, height: 108)
                                .padding(5)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            // 节点候选切换器（无 emoji，微圆点）
                            if let cands = ticket.candidates, cands.count > 1 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("选择连接节点：")
                                        .font(ArchiveTypography.monoScale(size: 10.5))
                                        .foregroundStyle(ArchivePalette.inkMuted)

                                    HStack(spacing: 6) {
                                        ForEach(cands) { cand in
                                            Button {
                                                Task { @MainActor in
                                                    if let updated = try? await APIClient.shared.fetchPairQRCode(hubURL: cand.url, ticket: ticket.ticket) {
                                                        var mutable = ticket
                                                        mutable.hubUrl = updated.hubUrl
                                                        mutable.qrPayload = updated.qrPayload
                                                        mutable.qrCodeDataUrl = updated.qrCodeDataUrl
                                                        issuedPairTicket = mutable
                                                        AudioFeedback.shared.playTink()
                                                    }
                                                }
                                            } label: {
                                                HStack(spacing: 5) {
                                                    Circle()
                                                        .fill(ticket.hubUrl == cand.url ? ArchivePalette.accentWarm : ArchivePalette.borderDivider)
                                                        .frame(width: 6, height: 6)
                                                    Text(cand.label)
                                                    Text("(\(cand.ip))")
                                                        .font(ArchiveTypography.monoScale(size: 10))
                                                        .opacity(0.7)
                                                }
                                                .font(ArchiveTypography.bodySans(size: 11, weight: ticket.hubUrl == cand.url ? .medium : .regular))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3.5)
                                                .background(ticket.hubUrl == cand.url ? ArchivePalette.accentWarm.opacity(0.12) : ArchivePalette.archiveSubtle)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .stroke(ticket.hubUrl == cand.url ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: 0.5)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            HStack(spacing: 8) {
                                Text(ticket.qrPayload)
                                    .font(ArchiveTypography.monoScale(size: 10.5))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ArchivePalette.archiveSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .textSelection(.enabled)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(ticket.qrPayload, forType: .string)
                                    AudioFeedback.shared.playTink()
                                    appState.showTemporaryBanner("已复制配对链接至剪贴板")
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                        Text("复制链接")
                                    }
                                }
                                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                            }
                        }
                    }
                }
                .padding(12)
                .background(ArchivePalette.archivePaper)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ArchivePalette.accentWarm.opacity(0.4), lineWidth: 0.8)
                )
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

                    Button("重命名") {
                        renamingDevice = dev
                        newDeviceNameInput = dev.name
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .buttonStyle(.plain)

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

    // MARK: - 3.5 分类标签字典管理
    private var categoryManagerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("04 · 分类标签字典管理")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            HStack(spacing: 6) {
                ForEach([("expense", "支出类目"), ("income", "收入类目"), ("gear", "随身装备"), ("project", "造物标签")], id: \.0) { scope, label in
                    PaperPillButton(
                        title: label,
                        isSelected: selectedCategoryScope == scope
                    ) {
                        selectedCategoryScope = scope
                        AudioFeedback.shared.playTink()
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("输入新分类标签…", text: $newCategoryNameInput)
                    .textFieldStyle(.plain)
                    .font(ArchiveTypography.bodySans(size: 12))
                    .padding(8)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ArchivePalette.borderDivider, lineWidth: 0.5)
                    )

                Button("+ 添加分类") {
                    let name = newCategoryNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    Task { @MainActor in
                        do {
                            _ = try await APIClient.shared.addCategoryOption(scope: selectedCategoryScope, name: name)
                            newCategoryNameInput = ""
                            await appState.loadConfigAndProfile()
                            allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
                            AudioFeedback.shared.playTink()
                        } catch {
                            authError = "添加分类失败: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(newCategoryNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            let currentScopeCats = allCategoriesList.filter { $0.scope == selectedCategoryScope }
            if currentScopeCats.isEmpty {
                Text("展示当前分类项。")
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(currentScopeCats) { cat in
                        HStack(spacing: 4) {
                            Text(cat.name)
                                .font(ArchiveTypography.bodySans(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            if cat.isBuiltin {
                                Text("预置")
                                    .font(ArchiveTypography.monoScale(size: 9))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            } else {
                                Spacer()
                                Button {
                                    Task { @MainActor in
                                        do {
                                            try await APIClient.shared.deleteCategoryOption(id: cat.id)
                                            await appState.loadConfigAndProfile()
                                            allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
                                            AudioFeedback.shared.playTink()
                                        } catch {
                                            authError = "删除分类失败: \(error.localizedDescription)"
                                        }
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                        )
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

            Divider().overlay(ArchivePalette.borderSubtle)

            VStack(alignment: .leading, spacing: 6) {
                Text("全量多格式文稿与数据导出")
                    .font(ArchiveTypography.bodySans(size: 12.5, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("数据 100% 属于你，永远可导出，格式开放且永久兼容：")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)

                HStack(spacing: 8) {
                    Button {
                        exportArchive(format: .markdown)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                            Text("导出 Markdown 日记")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .disabled(isExportingArchive)

                    Button {
                        exportArchive(format: .csv)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tablecells")
                            Text("导出 CSV 账目")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .disabled(isExportingArchive)

                    Button {
                        exportArchive(format: .json)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "curlybraces")
                            Text("导出全量 JSON 备份")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .disabled(isExportingArchive)
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
        if let list = try? await APIClient.shared.fetchTrustedDevices() {
            appState.trustedDevices = list
        }
    }

    private func decodeDataURLImage(_ dataURL: String?) -> NSImage? {
        guard let dataURL, let commaIdx = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: commaIdx)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }

    private func renameDeviceSheetView(dev: TrustedDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名受信任设备")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("设备名称", text: $newDeviceNameInput)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 13))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Button("取消") { renamingDevice = nil }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存名称") {
                    let targetId = dev.deviceId
                    let newName = newDeviceNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    renamingDevice = nil
                    Task { @MainActor in
                        do {
                            _ = try await APIClient.shared.updateDeviceName(id: targetId, name: newName)
                            await refreshDevicesList()
                            AudioFeedback.shared.playTink()
                        } catch {
                            authError = "重命名失败: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(newDeviceNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(ArchivePalette.archivePaper)
    }

    private func exportArchive(format: ArchiveExporter.ExportFormat) {
        let panel = NSSavePanel()
        switch format {
        case .markdown:
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "looseleaf-export-\(FormatUtils.beijingDateString()).md"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "looseleaf-transactions-\(FormatUtils.beijingDateString()).csv"
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "looseleaf-backup-\(FormatUtils.beijingDateString()).json"
        }

        if panel.runModal() == .OK, let targetURL = panel.url {
            isExportingArchive = true
            Task { @MainActor in
                let data = await ArchiveExporter.fetchAllRemoteAndExport(
                    format: format,
                    fallbackSnapshot: SyncManager.shared.currentSnapshot(),
                    fallbackProjects: appState.projects,
                    fallbackWishes: appState.wishes,
                    fallbackFootprints: appState.footprints
                )
                if let data {
                    try? data.write(to: targetURL, options: .atomic)
                    AudioFeedback.shared.playShutter()
                    appState.showTemporaryBanner("档案导出成功")
                } else {
                    appState.errorBanner = "导出生成失败"
                }
                isExportingArchive = false
            }
        }
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
        view.onCancelled = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.onCaptured = onCaptured
        nsView.onCancelled = {
            isRecording = false
        }
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class RecorderNSView: NSView {
    var onCaptured: ((Int, Int) -> Void)?
    var onCancelled: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancelled?()
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
