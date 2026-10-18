import SwiftUI
import Carbon
import UniformTypeIdentifiers

/// 配置中心分类标签枚举
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general = "偏好设置"
    case devices = "中枢与设备"
    case backup = "存储与备份"
    case categories = "分类字典"
    case about = "关于活页"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .devices: return "laptopcomputer.and.iphone"
        case .backup: return "archivebox"
        case .categories: return "tag"
        case .about: return "info.circle"
        }
    }
}

/// 活页集统一配置中心视图 (SettingsView) - Option A 选项卡轻量架构
/// 剔除工程调试杂质，分栏模块化呈现：纸本偏好、中枢设备、热备归档、分类字典与版本状态
@MainActor
public struct SettingsView: View {
    @Bindable var appState: AppState

    @State private var selectedTab: SettingsTab = .general

    @State private var ticketURIInput: String = ""
    @State private var isSubmittingAuth: Bool = false
    @State private var authFeedback: String?
    @State private var authError: String?

    // 签发新设备配对码状态
    @State private var issuedPairTicket: PairTicketResponse?

    // 设备重命名与吊销状态
    @State private var renamingDevice: TrustedDevice?
    @State private var newDeviceNameInput: String = ""
    @State private var showRevokeConfirm: Bool = false
    @State private var deviceToRevoke: TrustedDevice?
    @State private var showUnpairSelfConfirm: Bool = false

    // 分类字典管理状态
    @State private var selectedCategoryScope: String = "expense"
    @State private var isAddingCategoryInline: Bool = false
    @State private var inlineCategoryName: String = ""
    @State private var allCategoriesList: [CategoryOption] = []
    @State private var renamingCategory: CategoryOption?
    @State private var renameCategoryInput: String = ""
    @State private var isExportingArchive: Bool = false

    // 中枢系统级备份状态
    @State private var serverBackups: [ServerBackupItem] = []
    @State private var isLoadingServerBackups: Bool = false
    @State private var isCreatingServerBackup: Bool = false
    @State private var backupActionFeedback: String?
    @State private var backupActionError: String?
    @State private var backupToRestore: ServerBackupItem?
    @State private var showRestoreServerBackupConfirm: Bool = false
    @State private var backupToDelete: ServerBackupItem?
    @State private var showDeleteServerBackupConfirm: Bool = false

    // 对象存储与中枢灾备管理 (对标 Web StorageBackupModal.vue)
    @State private var backupSubTab: String = "backup" // "backup", "storage", "export"
    @State private var storageStatus: StorageStatus?
    @State private var isLoadingStorageStatus: Bool = false
    @State private var isTestingStorage: Bool = false
    @State private var isSavingStorage: Bool = false
    @State private var isResettingStorage: Bool = false
    @State private var isMigratingStorage: Bool = false
    @State private var storageFeedback: String?
    @State private var storageError: String?

    @State private var storageProviderType: String = "r2" // "r2" or "s3"
    @State private var showSecretKey: Bool = false
    @State private var showResetStorageConfirm: Bool = false
    @State private var storageAccountId: String = ""
    @State private var storageBucketName: String = ""
    @State private var storageEndpoint: String = ""
    @State private var storageAccessKeyId: String = ""
    @State private var storageSecretAccessKey: String = ""
    @State private var storagePublicDomain: String = ""
    @State private var storagePresignSeconds: Int = 1800


    // 全局热键录制状态
    @State private var hotKeyLabel: String = AppDelegate.hotKeyDisplayName
    @State private var isRecordingHotKey: Bool = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.8))

            // 选项卡主体呈现区
            Group {
                switch selectedTab {
                case .general:
                    generalTabContent
                case .devices:
                    devicesTabContent
                case .backup:
                    backupTabContent
                case .categories:
                    categoriesTabContent
                case .about:
                    aboutTabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
        }
        .frame(width: 820, height: 580)
        .background(ArchivePalette.archivePaper)
        .sheet(item: $renamingDevice) { dev in
            renameDeviceSheetView(dev: dev)
        }
        .sheet(item: $renamingCategory) { cat in
            renameCategorySheetView(cat: cat)
        }
        .confirmationDialog(
            "确认吊销该设备的接入授权？",
            isPresented: $showRevokeConfirm,
            titleVisibility: .visible
        ) {
            Button("吊销设备凭证", role: .destructive) {
                if let dev = deviceToRevoke {
                    revokeDeviceAction(dev)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("吊销后该伴生设备将无法继续同步或读取中枢生活档案。")
        }
        .confirmationDialog(
            "确认解除本机配对？",
            isPresented: $showUnpairSelfConfirm,
            titleVisibility: .visible
        ) {
            Button("解除配对并退出", role: .destructive) {
                Task { @MainActor in
                    await appState.disconnectDevice()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("解除配对将清空保存在本机钥匙串的受保护凭据，需重新扫码配对才能接入中枢。")
        }
        .confirmationDialog(
            "确认回滚还原整库？",
            isPresented: $showRestoreServerBackupConfirm,
            titleVisibility: .visible
        ) {
            Button("确认回滚覆盖", role: .destructive) {
                if let target = backupToRestore {
                    restoreServerBackupAction(target)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将从快照「\(backupToRestore?.filename ?? "")」恢复中枢数据库与媒体文件，现有未同步数据将被该快照覆盖。")
        }
        .confirmationDialog(
            "确认从中枢删除该备份快照？",
            isPresented: $showDeleteServerBackupConfirm,
            titleVisibility: .visible
        ) {
            Button("删除快照", role: .destructive) {
                if let target = backupToDelete {
                    deleteServerBackupAction(target)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将从中枢永久移除该备份文件，无法再回滚至此时间节点。")
        }
        .confirmationDialog(
            "切换为本地磁盘存储",
            isPresented: $showResetStorageConfirm,
            titleVisibility: .visible
        ) {
            Button("确认恢复本地存储", role: .destructive) {
                resetStorageAction()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要关闭云端对象存储并恢复为本地磁盘存储模式吗？新上传的文件将直接保存在服务端本地磁盘 (/media)。")
        }
        .task {
            if appState.isPaired {
                await refreshDevicesList()
                allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
                await loadServerBackups()
                await loadStorageStatusAction()
            }
        }
    }

    // MARK: - 顶栏与选项卡切换
    private var headerBar: some View {
        HStack(spacing: 0) {
            Text("配置中心")
                .font(ArchiveTypography.editorialSerif(size: 16, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            Spacer()

            // 居中分段选项卡胶囊 (绝对单行不折叠)
            HStack(spacing: 3) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                        AudioFeedback.shared.playTink()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 10.5, weight: .medium))
                            Text(tab.rawValue)
                                .font(ArchiveTypography.bodySans(size: 11.5, weight: selectedTab == tab ? .semibold : .regular))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? ArchivePalette.archivePaper : Color.clear)
                        .foregroundStyle(selectedTab == tab ? ArchivePalette.inkPrimary : ArchivePalette.inkSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedTab == tab ? ArchivePalette.borderSubtle : Color.clear, lineWidth: 0.5)
                        )
                        .shadow(color: selectedTab == tab ? Color.black.opacity(0.04) : Color.clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ArchivePalette.borderSubtle.opacity(0.7), lineWidth: 0.5)
            )

            Spacer()

            // 右上角关闭按钮 (支持 Esc 快捷键与点击空白退出)
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    appState.showSettingsSheet = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .frame(width: 26, height: 26)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("关闭配置中心 (Esc / 点击外部空白)")
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 1. 偏好设置 Tab
    private var generalTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 纸本外观主题
                VStack(alignment: .leading, spacing: 10) {
                    Text("纸本外观主题")
                        .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    HStack(spacing: 12) {
                        themeSwatchCard(
                            mode: .system,
                            title: "跟随系统",
                            subtitle: "随 macOS 自动切换浅色/暗色",
                            icon: "circle.lefthalf.filled"
                        )
                        themeSwatchCard(
                            mode: .paper,
                            title: "暖色棉纸",
                            subtitle: "天然棉纸米黄底色与炭黑墨迹",
                            icon: "sun.max.fill"
                        )
                        themeSwatchCard(
                            mode: .darkroom,
                            title: "暗房安全灯",
                            subtitle: "低照度琥珀暗调与微光纸本",
                            icon: "moon.fill"
                        )
                    }
                }

                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))

                // 拟物声学与触觉反馈
                VStack(alignment: .leading, spacing: 10) {
                    Text("拟物声学与物理触觉")
                        .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    VStack(spacing: 8) {
                        HStack(alignment: .center) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("机械快门与翻纸音效")
                                    .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                Text("提交闪念、记账、快照完成时播放 32ms 低延迟真实机械快门与轻纸回弹声")
                                    .font(ArchiveTypography.bodySans(size: 10.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }

                            Spacer()

                            Button("试听快门") {
                                AudioFeedback.shared.playShutter()
                            }
                            .font(ArchiveTypography.bodySans(size: 11))
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                            Toggle("", isOn: $appState.soundEnabled)
                                .tint(ArchivePalette.accentWarm)
                                .labelsHidden()
                        }
                        .padding(12)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        HStack(alignment: .center) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("触控板物理触觉反馈 (Force Touch Haptics)")
                                    .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                Text("拖拽照片归档与触点交互时，通过 Taptic Engine 传递轻微物理微震触感")
                                    .font(ArchiveTypography.bodySans(size: 10.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }

                            Spacer()

                            Toggle("", isOn: $appState.hapticsEnabled)
                                .tint(ArchivePalette.accentWarm)
                                .labelsHidden()
                        }
                        .padding(12)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))

                // 全局极速手账悬浮窗快捷键
                VStack(alignment: .leading, spacing: 10) {
                    Text("全局快捷键")
                        .font(ArchiveTypography.editorialSerif(size: 13.5, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    HStack {
                        Image(systemName: "command")
                            .font(.system(size: 13))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("全局呼出极速手账悬浮窗")
                                .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                            Text("在任意应用程序窗口下随手唤起闪念录入与随行记账")
                                .font(ArchiveTypography.bodySans(size: 10.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text(hotKeyLabel)
                                .font(ArchiveTypography.monoScale(size: 11, weight: .semibold))
                                .foregroundStyle(ArchivePalette.inkPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.borderSubtle, lineWidth: 1))
                        }

                        if isRecordingHotKey {
                            Text("按下新组合键…")
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)

                            HotKeyRecorderView(isRecording: $isRecordingHotKey) { keyCode, modifiers in
                                (NSApp.delegate as? AppDelegate)?.applyHotKey(keyCode: keyCode, carbonModifiers: modifiers)
                                hotKeyLabel = AppDelegate.hotKeyDisplayName
                                isRecordingHotKey = false
                                AudioFeedback.shared.playTink()
                            }
                            .frame(width: 1, height: 1)
                            .opacity(0.01)
                        } else {
                            Button("修改") {
                                isRecordingHotKey = true
                            }
                            .font(ArchiveTypography.bodySans(size: 11))
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        }
                    }
                    .padding(12)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(20)
        }
    }

    private func themeSwatchCard(mode: AppearanceMode, title: String, subtitle: String, icon: String) -> some View {
        let isSelected = appState.appearanceMode == mode
        return Button {
            appState.appearanceMode = mode
            AudioFeedback.shared.playTink()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? ArchivePalette.accentWarm : ArchivePalette.inkSecondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                }
                Text(title)
                    .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text(subtitle)
                    .font(ArchiveTypography.bodySans(size: 9.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? ArchivePalette.accentWarm : ArchivePalette.borderSubtle, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. 中枢与设备 Tab
    private var devicesTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 中枢连接状态指示条
                HStack(spacing: 8) {
                    Circle()
                        .fill(ArchivePalette.accentMoss)
                        .frame(width: 7, height: 7)
                    Text("数据中枢已连接")
                        .font(ArchiveTypography.bodySans(size: 11.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                    Text(appState.hubURLString)
                        .font(ArchiveTypography.monoScale(size: 10.5))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    Spacer()

                    Button {
                        Task { @MainActor in
                            issuedPairTicket = try? await APIClient.shared.initPairing()
                            AudioFeedback.shared.playPaperFlip()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 10))
                            Text("签发新设备配对凭证")
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
                .padding(10)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // 配对工单二维码卡片 (若已生成)
                if let ticket = issuedPairTicket {
                    pairTicketBanner(ticket: ticket)
                }

                // 未配对时的凭证导入行
                if !appState.isPaired {
                    unpairedInputBar
                }

                // 本机客户端置顶展示
                let currentDeviceId = CredentialStore.getDeviceId()
                let selfDev = appState.trustedDevices.first(where: { $0.deviceId == currentDeviceId })
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前使用的设备")
                        .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    HStack(spacing: 12) {
                        Image(systemName: "macbook")
                            .font(.system(size: 18))
                            .foregroundStyle(ArchivePalette.accentMoss)
                            .frame(width: 26)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(selfDev?.name ?? "迟暮的 MacBook Air")
                                    .font(ArchiveTypography.bodySans(size: 12.5, weight: .semibold))
                                    .foregroundStyle(ArchivePalette.inkPrimary)
                                Text("本机 · 当前客户端")
                                    .font(ArchiveTypography.monoScale(size: 9))
                                    .foregroundStyle(ArchivePalette.accentMoss)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                            }
                            Text("macOS 原生客户端 · 刚刚活跃")
                                .font(ArchiveTypography.monoScale(size: 9.5))
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

                        Button("解除本机配对") {
                            showUnpairSelfConfirm = true
                        }
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // 受信任伴生设备组
                let otherDevices = appState.trustedDevices.filter { $0.deviceId != currentDeviceId }
                VStack(alignment: .leading, spacing: 6) {
                    Text("已授权伴生设备 (\(otherDevices.count))")
                        .font(ArchiveTypography.bodySans(size: 11, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkMuted)

                    if otherDevices.isEmpty {
                        Text("暂无其他已配对伴生设备，点击上方「签发新设备配对凭证」可在手机或 Web 端扫码接入。")
                            .font(ArchiveTypography.bodySans(size: 11))
                            .foregroundStyle(ArchivePalette.inkMuted)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(otherDevices) { dev in
                                HStack(spacing: 12) {
                                    Image(systemName: devicePlatformIcon(dev.platform, isSelf: false))
                                        .font(.system(size: 15))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .frame(width: 26)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(dev.name)
                                                .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
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
                                        deviceToRevoke = dev
                                        showRevokeConfirm = true
                                    }
                                    .font(ArchiveTypography.bodySans(size: 11))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
            .padding(20)
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
                        AudioFeedback.shared.playTink()
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

    // MARK: - 3. 存储与灾备 Tab
    private var backupTabContent: some View {
        VStack(spacing: 0) {
            // 次级选项卡切换胶囊 (对标 Web StorageBackupModal.vue)
            HStack(spacing: 8) {
                PaperPillButton(
                    title: "全量快照与灾备 (\(serverBackups.count)/7)",
                    isSelected: backupSubTab == "backup"
                ) {
                    backupSubTab = "backup"
                    AudioFeedback.shared.playTink()
                }

                PaperPillButton(
                    title: "对象存储设置",
                    isSelected: backupSubTab == "storage"
                ) {
                    backupSubTab = "storage"
                    AudioFeedback.shared.playTink()
                }

                PaperPillButton(
                    title: "文稿与数据导出",
                    isSelected: backupSubTab == "export"
                ) {
                    backupSubTab = "export"
                    AudioFeedback.shared.playTink()
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(ArchivePalette.archivePaper)

            Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch backupSubTab {
                    case "backup":
                        serverBackupSubView
                    case "storage":
                        objectStorageSubView
                    case "export":
                        exportDataSubView
                    default:
                        serverBackupSubView
                    }
                }
                .padding(20)
            }
        }
    }

    private var serverBackupSubView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 顶栏缓存体量与全量快照触发
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("中枢系统级全量热备")
                            .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("\(serverBackups.count)/7 份")
                            .font(ArchiveTypography.monoScale(size: 9.5))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }
                    Text("本地缓存：散页 \(appState.entries.count) 篇 · 账目 \(appState.transactions.count) 笔 · 待发 \(appState.outboxItems.count) 项 · 目的地：\(storageStatus?.configured == true ? "Cloudflare R2" : "中枢本地磁盘")")
                        .font(ArchiveTypography.monoScale(size: 10))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        Task { @MainActor in
                            await loadServerBackups()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            if isLoadingServerBackups {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9))
                            }
                            Text("刷新")
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                    Button {
                        createServerBackupAction()
                    } label: {
                        HStack(spacing: 4) {
                            if isCreatingServerBackup {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 10))
                            }
                            Text(isCreatingServerBackup ? "正在生成…" : "立即生成快照")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    .disabled(isCreatingServerBackup || !appState.isPaired)
                }
            }

            // 极简备份策略说明
            Text("每日自动热备整库，保留最新 7 份快照，支持 Cloudflare R2 与本地存储双重冗余，可在任一时间节点一键回滚整库。")
                .font(ArchiveTypography.bodySans(size: 11))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if let fb = backupActionFeedback {
                Text(fb)
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.accentMoss)
            }
            if let err = backupActionError {
                Text(err)
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            // 历史快照清单
            Text("历史快照归档清单 (\(serverBackups.count)/7)")
                .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                .foregroundStyle(ArchivePalette.inkPrimary)

            if isLoadingServerBackups && serverBackups.isEmpty {
                ProgressView().padding(.vertical, 12)
            } else if serverBackups.isEmpty {
                Text("暂无中枢备份快照，您可以点击右上角「立即生成快照」创建首个全量热备。")
                    .font(ArchiveTypography.bodySans(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 6) {
                    ForEach(serverBackups) { backup in
                        HStack(spacing: 10) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 13))
                                .foregroundStyle(ArchivePalette.accentMoss)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("\(backup.formattedDate) 快照")
                                        .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                    Text(backup.storageTypeBadge)
                                        .font(ArchiveTypography.monoScale(size: 9))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(ArchivePalette.archivePaper)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                }
                                Text("\(backup.formattedSize) · \(backup.filename)")
                                    .font(ArchiveTypography.monoScale(size: 9.5))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                downloadServerBackupAction(backup)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.down.to.line")
                                        .font(.system(size: 9))
                                    Text("下载至 Mac")
                                }
                            }
                            .font(ArchiveTypography.bodySans(size: 10.5))
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                            Button {
                                backupToRestore = backup
                                showRestoreServerBackupConfirm = true
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 9))
                                    Text("回滚还原")
                                }
                            }
                            .font(ArchiveTypography.bodySans(size: 10.5))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))

                            Button {
                                backupToDelete = backup
                                showDeleteServerBackupConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private var objectStorageSubView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 状态概览卡片
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: storageStatus?.configured == true ? "cloud.fill" : "internaldrive")
                        .foregroundStyle(storageStatus?.configured == true ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .font(.system(size: 14))

                    Text(storageStatus?.configured == true ? "当前接入：\(storageStatus?.provider ?? "Cloudflare R2") (已挂载)" : "当前接入：中枢本地磁盘存储 (/media)")
                        .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                Text("·")
                    .foregroundStyle(ArchivePalette.inkMuted)

                Text("媒体文件 \(storageStatus?.localFileCount ?? 0) 件 (\(formatByteCount(storageStatus?.localTotalBytes ?? 0)))")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkSecondary)

                Spacer()

                if storageStatus?.configured == true {
                    Button {
                        migrateStorageAction()
                    } label: {
                        HStack(spacing: 4) {
                            if isMigratingStorage {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                            }
                            Text(isMigratingStorage ? "正在同步…" : "双向同步媒体")
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .disabled(isMigratingStorage)
                }
            }
            .padding(12)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // 模式切换与凭据表单卡片
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("对象存储接入凭据")
                        .font(ArchiveTypography.editorialSerif(size: 13, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Spacer()

                    HStack(spacing: 2) {
                        Button("Cloudflare R2") {
                            storageProviderType = "r2"
                        }
                        .font(ArchiveTypography.bodySans(size: 11, weight: storageProviderType == "r2" ? .semibold : .regular))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(storageProviderType == "r2" ? ArchivePalette.inkPrimary : Color.clear)
                        .foregroundStyle(storageProviderType == "r2" ? ArchivePalette.archivePaper : ArchivePalette.inkSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .buttonStyle(.plain)

                        Button("S3 兼容协议") {
                            storageProviderType = "s3"
                        }
                        .font(ArchiveTypography.bodySans(size: 11, weight: storageProviderType == "s3" ? .semibold : .regular))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(storageProviderType == "s3" ? ArchivePalette.inkPrimary : Color.clear)
                        .foregroundStyle(storageProviderType == "s3" ? ArchivePalette.archivePaper : ArchivePalette.inkSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                }

                // 表单网格
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(storageProviderType == "r2" ? "Cloudflare 账户 ID *" : "S3 服务端点 (Endpoint) *")
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                            TextField(
                                storageProviderType == "r2" ? "32 位 Cloudflare Account ID" : "https://s3.ap-northeast-1.amazonaws.com",
                                text: storageProviderType == "r2" ? $storageAccountId : $storageEndpoint
                            )
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.monoScale(size: 11.5))
                            .padding(7)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("存储桶名称 (Bucket Name) *")
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                            TextField("looseleaf-bucket", text: $storageBucketName)
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.monoScale(size: 11.5))
                                .padding(7)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }
                    }

                    GridRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("访问密钥 ID (Access Key ID) *")
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                            TextField("Access Key ID", text: $storageAccessKeyId)
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.monoScale(size: 11.5))
                                .padding(7)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("私有访问密钥 (Secret Access Key)")
                                    .font(ArchiveTypography.bodySans(size: 11))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                if storageStatus?.hasSecretKey == true {
                                    Text("已配置")
                                        .font(ArchiveTypography.monoScale(size: 9))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                }
                            }

                            HStack(spacing: 4) {
                                if showSecretKey {
                                    TextField(storageStatus?.hasSecretKey == true ? "留空保持已存密钥" : "Secret Access Key", text: $storageSecretAccessKey)
                                        .textFieldStyle(.plain)
                                } else {
                                    SecureField(storageStatus?.hasSecretKey == true ? "留空保持已存密钥" : "Secret Access Key", text: $storageSecretAccessKey)
                                        .textFieldStyle(.plain)
                                }

                                Button {
                                    showSecretKey.toggle()
                                } label: {
                                    Image(systemName: showSecretKey ? "eye.slash" : "eye")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .font(ArchiveTypography.monoScale(size: 11.5))
                            .padding(7)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }
                    }

                    GridRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("公网访问加速域名 (可选)")
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                            TextField("https://media.example.com", text: $storagePublicDomain)
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.monoScale(size: 11.5))
                                .padding(7)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("临时下载链接有效时长")
                                .font(ArchiveTypography.bodySans(size: 11))
                                .foregroundStyle(ArchivePalette.inkSecondary)

                            Picker("", selection: $storagePresignSeconds) {
                                Text("15 分钟 (高安全)").tag(900)
                                Text("30 分钟 (推荐)").tag(1800)
                                Text("1 小时").tag(3600)
                                Text("6 小时").tag(21600)
                                Text("24 小时").tag(86400)
                                Text("7 天 (最长上限)").tag(604800)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .padding(.vertical, 2)
                        }
                    }
                }

                // 提示与反馈信息
                if let fb = storageFeedback {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.accentMoss)
                        Text(fb)
                            .font(ArchiveTypography.bodySans(size: 11))
                            .foregroundStyle(ArchivePalette.accentMoss)
                    }
                    .padding(.top, 2)
                }

                if let err = storageError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text(err)
                            .font(ArchiveTypography.bodySans(size: 11))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                    .padding(.top, 2)
                }

                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6)).padding(.vertical, 4)

                // 操作按钮栏
                HStack {
                    if storageStatus?.configured == true {
                        Button {
                            showResetStorageConfirm = true
                        } label: {
                            HStack(spacing: 4) {
                                if isResettingStorage {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 9))
                                }
                                Text(isResettingStorage ? "正在切换…" : "恢复为本地磁盘存储")
                            }
                        }
                        .font(ArchiveTypography.bodySans(size: 11))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .buttonStyle(.plain)
                        .disabled(isResettingStorage || isSavingStorage || isTestingStorage)
                    }

                    Spacer()

                    Button {
                        testStorageAction()
                    } label: {
                        HStack(spacing: 4) {
                            if isTestingStorage {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                            }
                            Text(isTestingStorage ? "握手测试中…" : "测试连通性")
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .disabled(isTestingStorage || isSavingStorage)

                    Button {
                        saveStorageAction()
                    } label: {
                        HStack(spacing: 4) {
                            if isSavingStorage {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            Text(isSavingStorage ? "保存中…" : "保存并挂载配置")
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 11))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    .disabled(isSavingStorage || isTestingStorage)
                }
            }
            .padding(14)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var exportDataSubView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("单次多格式全量文稿导出")
                .font(ArchiveTypography.editorialSerif(size: 14, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            Text("Loose-Leaf 支持完全自主掌控数据。导出文件可脱离任何中枢与网络，以标准纯文本格式长期封存或在任意 Markdown 编辑器与表格应用中打开。")
                .font(ArchiveTypography.bodySans(size: 11.5))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .lineSpacing(3)

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                        .foregroundStyle(ArchivePalette.accentMoss)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Markdown 日记卷宗 (.md)")
                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("包含所有日记手账正文、天气、城市、标签及配图元数据。")
                            .font(ArchiveTypography.bodySans(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    Spacer()

                    Button("导出 Markdown") { exportArchive(format: .markdown) }
                        .font(ArchiveTypography.bodySans(size: 11))
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .disabled(isExportingArchive)
                }
                .padding(12)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 12) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 16))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CSV 资产流水账目 (.csv)")
                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("与 Numbers / Excel 完全兼容，方便财务分析与图表统计。")
                            .font(ArchiveTypography.bodySans(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    Spacer()

                    Button("导出 CSV 账目") { exportArchive(format: .csv) }
                        .font(ArchiveTypography.bodySans(size: 11))
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .disabled(isExportingArchive)
                }
                .padding(12)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 12) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 16))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("全量结构化 JSON 归档 (.json)")
                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("完整包含散页、账目、造物项目、心愿清单及足迹等全部原始字段。")
                            .font(ArchiveTypography.bodySans(size: 10.5))
                            .foregroundStyle(ArchivePalette.inkMuted)
                    }

                    Spacer()

                    Button("导出 JSON 全量") { exportArchive(format: .json) }
                        .font(ArchiveTypography.bodySans(size: 11))
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                        .disabled(isExportingArchive)
                }
                .padding(12)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - 4. 分类字典 Tab
    private var currentDisplayCategories: [CategoryOption] {
        let matched = allCategoriesList.filter { $0.scope == selectedCategoryScope }
        if !matched.isEmpty { return matched }
        // 兜底保障：即使离线或初次加载也呈现默认分类，绝不留白
        let defaults: [String] = {
            switch selectedCategoryScope {
            case "expense": return appState.expenseCategories
            case "income": return appState.incomeCategories
            case "gear": return appState.gearCategories
            case "payment": return appState.paymentMethods
            case "project": return appState.projectCategories
            default: return []
            }
        }()
        return defaults.enumerated().map { index, name in
            CategoryOption(id: -(index + 1), scope: selectedCategoryScope, name: name, sortOrder: index, isBuiltin: true)
        }
    }

    private var categoriesTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 类目分类范围切换
                HStack(spacing: 6) {
                    ForEach([
                        ("expense", "支出类目"),
                        ("income", "收入类目"),
                        ("gear", "随身装备"),
                        ("payment", "支付方式"),
                        ("project", "造物分类")
                    ], id: \.0) { scope, label in
                        PaperPillButton(
                            title: label,
                            isSelected: selectedCategoryScope == scope
                        ) {
                            selectedCategoryScope = scope
                            AudioFeedback.shared.playTink()
                        }
                    }

                    Spacer()

                    Button {
                        Task { @MainActor in
                            do {
                                try await APIClient.shared.resetCategories(scope: selectedCategoryScope)
                                await appState.loadConfigAndProfile()
                                allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
                                AudioFeedback.shared.playPaperFlip()
                                appState.showTemporaryBanner("已恢复「\(selectedCategoryScope)」默认预置分类")
                            } catch {
                                authError = "恢复分类失败: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9))
                            Text("恢复默认")
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: 10.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                    .buttonStyle(.plain)
                }

                // 纸墨流式标签云
                FlowTagLayout(spacing: 8) {
                    ForEach(currentDisplayCategories) { cat in
                        HStack(spacing: 5) {
                            Text(cat.name)
                                .font(ArchiveTypography.bodySans(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkPrimary)

                            if cat.id > 0 {
                                Button {
                                    renamingCategory = cat
                                    renameCategoryInput = cat.name
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 8))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    deleteCategoryAction(cat)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                        )
                    }

                    // 行内即时添加新分类
                    if isAddingCategoryInline {
                        HStack(spacing: 4) {
                            TextField("新分类…", text: $inlineCategoryName)
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.bodySans(size: 11.5))
                                .frame(width: 80)
                                .onSubmit { submitInlineNewCategory() }

                            Button { submitInlineNewCategory() } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(ArchivePalette.accentWarm)
                            }
                            .buttonStyle(.plain)

                            Button { isAddingCategoryInline = false } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ArchivePalette.archivePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.accentWarm, lineWidth: 0.8))
                    } else {
                        Button {
                            isAddingCategoryInline = true
                            inlineCategoryName = ""
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .medium))
                                Text("添加分类")
                                    .font(ArchiveTypography.bodySans(size: 11))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - 5. 关于活页 Tab (包含原地平滑检查更新)
    private var aboutTabContent: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 12)

            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(ArchivePalette.accentMoss)

            VStack(spacing: 4) {
                Text("Loose-Leaf · 活页集")
                    .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Text("版本 1.5.0 (Build 15) · 原生 Apple Silicon")
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }

            // 平滑原地更新卡片
            VStack(spacing: 8) {
                let checker = UpdateChecker.shared
                if checker.isChecking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在检查最新版本…")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }
                } else if checker.isUpdating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在下载并应用最新版本…")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.accentWarm)
                    }
                } else if let update = checker.availableUpdate {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(ArchivePalette.accentWarm)
                        Text("发现新版本 \(update.tagName)")
                            .font(ArchiveTypography.bodySans(size: 12, weight: .medium))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Button("立即更新到 \(update.tagName)") {
                            Task { @MainActor in
                                await checker.performInAppUpdate()
                            }
                        }
                        .font(ArchiveTypography.bodySans(size: 11))
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ArchivePalette.accentMoss)
                            .font(.system(size: 12))
                        Text("当前已是最新版本 (v\(checker.currentVersion))")
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Button("重新检查更新") {
                            Task { @MainActor in
                                await checker.checkForUpdates(isUserInitiated: true)
                            }
                        }
                        .font(ArchiveTypography.bodySans(size: 10.5))
                        .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            VStack(spacing: 4) {
                Text("以纸为介，散页成卷。生活原色，自当留存。")
                    .font(ArchiveTypography.editorialSerif(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkSecondary)
                Text("Local-First 本地优先 · SQLite + R2 冗余热备 · 拟物声学微触觉")
                    .font(ArchiveTypography.monoScale(size: 9.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: - 辅助操作方法与 Sheet 弹窗

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
        .padding(18)
        .frame(width: 300)
        .background(ArchivePalette.archivePaper)
    }

    private func renameCategorySheetView(cat: CategoryOption) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("修改分类名称")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            TextField("分类名称", text: $renameCategoryInput)
                .textFieldStyle(.plain)
                .font(ArchiveTypography.bodySans(size: 12.5))
                .padding(8)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Button("取消") { renamingCategory = nil }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存修改") {
                    let newName = renameCategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    renamingCategory = nil
                    Task { @MainActor in
                        do {
                            _ = try await APIClient.shared.updateCategoryOption(id: cat.id, name: newName)
                            await appState.loadConfigAndProfile()
                            allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
                            AudioFeedback.shared.playTink()
                        } catch {
                            authError = "修改分类失败: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(renameCategoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func submitInlineNewCategory() {
        let name = inlineCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            isAddingCategoryInline = false
            return
        }
        Task { @MainActor in
            do {
                _ = try await APIClient.shared.addCategoryOption(scope: selectedCategoryScope, name: name)
                inlineCategoryName = ""
                isAddingCategoryInline = false
                await appState.loadConfigAndProfile()
                allCategoriesList = (try? await APIClient.shared.fetchCategories()) ?? []
                AudioFeedback.shared.playTink()
            } catch {
                authError = "添加分类失败: \(error.localizedDescription)"
            }
        }
    }

    private func deleteCategoryAction(_ cat: CategoryOption) {
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
    }

    private func loadServerBackups() async {
        guard appState.isPaired else { return }
        isLoadingServerBackups = true
        defer { isLoadingServerBackups = false }
        do {
            serverBackups = try await APIClient.shared.fetchServerBackups()
            backupActionError = nil
        } catch {
            backupActionError = "获取中枢备份列表失败: \(error.localizedDescription)"
        }
    }

    private func createServerBackupAction() {
        guard !isCreatingServerBackup else { return }
        isCreatingServerBackup = true
        backupActionFeedback = nil
        backupActionError = nil
        Task { @MainActor in
            defer { isCreatingServerBackup = false }
            do {
                let item = try await APIClient.shared.createServerBackupNow()
                backupActionFeedback = "中枢快照生成成功：\(item.filename)"
                serverBackups = try await APIClient.shared.fetchServerBackups()
                AudioFeedback.shared.playShutter()
            } catch {
                backupActionError = "生成中枢备份失败: \(error.localizedDescription)"
            }
        }
    }

    private func downloadServerBackupAction(_ item: ServerBackupItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = item.filename
        if panel.runModal() == .OK, let targetURL = panel.url {
            Task { @MainActor in
                do {
                    let (data, _) = try await APIClient.shared.downloadServerBackup(filename: item.filename)
                    try data.write(to: targetURL, options: .atomic)
                    backupActionFeedback = "已成功下载「\(item.filename)」至本地"
                    AudioFeedback.shared.playTink()
                } catch {
                    backupActionError = "下载备份失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteServerBackupAction(_ item: ServerBackupItem) {
        Task { @MainActor in
            do {
                serverBackups = try await APIClient.shared.deleteServerBackup(filename: item.filename)
                backupActionFeedback = "已从中枢删除快照「\(item.filename)」"
                AudioFeedback.shared.playTink()
            } catch {
                backupActionError = "删除备份失败: \(error.localizedDescription)"
            }
        }
    }

    private func restoreServerBackupAction(_ item: ServerBackupItem) {
        Task { @MainActor in
            do {
                try await APIClient.shared.restoreServerBackup(filename: item.filename)
                backupActionFeedback = "中枢已从快照成功回滚还原，正在同步最新状态…"
                AudioFeedback.shared.playShutter()
                await appState.refreshAll(forceFull: true)
                await loadServerBackups()
            } catch {
                backupActionError = "回滚还原失败: \(error.localizedDescription)"
            }
        }
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

    // MARK: - 云端对象存储灾备动作 (Storage Management Actions)

    private func formatByteCount(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024.0 {
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.2f GB", gb)
    }

    private func syncStorageFormWithStatus(_ status: StorageStatus?) {
        guard let status else { return }
        storageAccountId = status.accountId ?? ""
        storageBucketName = status.bucket ?? ""
        storageEndpoint = status.endpoint ?? ""
        storageAccessKeyId = status.accessKeyId ?? ""
        storagePublicDomain = status.publicDomain ?? ""
        storagePresignSeconds = status.presignExpireSeconds ?? 1800

        if let ep = status.endpoint, !ep.isEmpty, !ep.contains(".r2.cloudflarestorage.com") {
            storageProviderType = "s3"
        } else {
            storageProviderType = "r2"
        }
    }

    private func loadStorageStatusAction() async {
        guard appState.isPaired else { return }
        isLoadingStorageStatus = true
        defer { isLoadingStorageStatus = false }
        do {
            let status = try await APIClient.shared.fetchStorageStatus()
            storageStatus = status
            syncStorageFormWithStatus(status)
        } catch {
            storageError = "加载对象存储状态失败: \(error.localizedDescription)"
        }
    }

    private func testStorageAction() {
        guard !isTestingStorage else { return }
        storageFeedback = nil
        storageError = nil

        let bucket = storageBucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = storageAccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        if bucket.isEmpty {
            storageError = "请填写存储桶名称 (Bucket Name)"
            return
        }
        if accessKey.isEmpty {
            storageError = "请填写 Access Key ID"
            return
        }

        let endpoint: String = {
            if storageProviderType == "r2" {
                let acc = storageAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !acc.isEmpty && storageEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "https://\(acc).r2.cloudflarestorage.com"
                }
            }
            return storageEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        let payload = StorageConfigPayload(
            accountId: storageAccountId.trimmingCharacters(in: .whitespacesAndNewlines),
            accessKeyId: accessKey,
            secretAccessKey: storageSecretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            bucketName: bucket,
            endpoint: endpoint,
            publicDomain: storagePublicDomain.trimmingCharacters(in: .whitespacesAndNewlines),
            presignExpireSeconds: storagePresignSeconds
        )

        isTestingStorage = true
        Task { @MainActor in
            defer { isTestingStorage = false }
            do {
                let res = try await APIClient.shared.testStorageConfig(payload)
                let latencyText = res.latencyMs != nil ? " · 延迟 \(res.latencyMs!)ms" : ""
                storageFeedback = "\(res.message ?? "握手测试成功，读写校验正常")\(latencyText)"
                AudioFeedback.shared.playTink()
            } catch {
                storageError = "连接测试失败: \(error.localizedDescription)"
            }
        }
    }

    private func saveStorageAction() {
        guard !isSavingStorage else { return }
        storageFeedback = nil
        storageError = nil

        let bucket = storageBucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = storageAccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        if bucket.isEmpty {
            storageError = "请填写存储桶名称 (Bucket Name)"
            return
        }
        if accessKey.isEmpty {
            storageError = "请填写 Access Key ID"
            return
        }

        let endpoint: String = {
            if storageProviderType == "r2" {
                let acc = storageAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !acc.isEmpty && storageEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "https://\(acc).r2.cloudflarestorage.com"
                }
            }
            return storageEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        let payload = StorageConfigPayload(
            accountId: storageAccountId.trimmingCharacters(in: .whitespacesAndNewlines),
            accessKeyId: accessKey,
            secretAccessKey: storageSecretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            bucketName: bucket,
            endpoint: endpoint,
            publicDomain: storagePublicDomain.trimmingCharacters(in: .whitespacesAndNewlines),
            presignExpireSeconds: storagePresignSeconds
        )

        isSavingStorage = true
        Task { @MainActor in
            defer { isSavingStorage = false }
            do {
                let status = try await APIClient.shared.updateStorageConfig(payload)
                storageStatus = status
                storageSecretAccessKey = ""
                storageFeedback = "配置已保存并生效，对象存储已成功热重载挂载"
                AudioFeedback.shared.playPaperFlip()
            } catch {
                storageError = "保存配置失败: \(error.localizedDescription)"
            }
        }
    }

    private func resetStorageAction() {
        guard !isResettingStorage else { return }
        isResettingStorage = true
        storageFeedback = nil
        storageError = nil
        Task { @MainActor in
            defer { isResettingStorage = false }
            do {
                let status = try await APIClient.shared.resetStorageConfig()
                storageStatus = status
                storageSecretAccessKey = ""
                storageFeedback = "已恢复为本地磁盘存储模式"
                AudioFeedback.shared.playTink()
            } catch {
                storageError = "恢复本地存储失败: \(error.localizedDescription)"
            }
        }
    }

    private func migrateStorageAction() {
        guard !isMigratingStorage else { return }
        isMigratingStorage = true
        storageFeedback = nil
        storageError = nil
        AudioFeedback.shared.playTink()
        Task { @MainActor in
            defer { isMigratingStorage = false }
            do {
                let res = try await APIClient.shared.migrateStorageMedia()
                let summary = "双向增量同步完成：上传 \(res.uploadedToR2 ?? 0) 项，拉取 \(res.downloadedToLocal ?? 0) 项"
                storageFeedback = summary
                AudioFeedback.shared.playPaperFlip()
                await loadStorageStatusAction()
            } catch {
                storageError = "增量同步失败: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 流式自适应换行布局 (FlowTagLayout)

public struct FlowTagLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        height = currentY + lineHeight
        return CGSize(width: width, height: max(height, 28))
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

// MARK: - 全局热键录制控件 (HotKeyRecorder)

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
            return
        }
        var carbonModifiers: Int = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { carbonModifiers |= Int(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= Int(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= Int(shiftKey) }
        if flags.contains(.control) { carbonModifiers |= Int(controlKey) }
        guard carbonModifiers != 0 else { return }
        onCaptured?(Int(event.keyCode), carbonModifiers)
    }
}
