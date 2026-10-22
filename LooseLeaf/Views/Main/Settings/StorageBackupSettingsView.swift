import SwiftUI

/// 存储与备份（左侧菜单「存储与备份」入口）：中枢全量 ZIP 快照灾备与 R2/S3 对象存储配置
@MainActor
struct StorageBackupSettingsView: View {
    @Bindable var appState: AppState

    // 中枢系统级备份状态
    @State private var serverBackups: [ServerBackupItem] = []
    @State private var isLoadingServerBackups: Bool = false
    @State private var isCreatingServerBackup: Bool = false
    @State private var backupActionFeedback: String?
    @State private var backupActionError: String?

    // 对象存储与中枢灾备管理 (仅保留全量 ZIP 快照与 R2/S3 对象存储)
    @State private var backupSubTab: String = "backup" // "backup", "storage"
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
    @State private var storageAccountId: String = ""
    @State private var storageBucketName: String = ""
    @State private var storageEndpoint: String = ""
    @State private var storageAccessKeyId: String = ""
    @State private var storageSecretAccessKey: String = ""
    @State private var storagePublicDomain: String = ""
    @State private var storagePresignSeconds: Int = 1800

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
            // 次级选项卡切换胶囊 (仅保留全量 ZIP 快照与 R2/S3 对象存储)
            HStack(spacing: ArchiveSpacing.s) {
                PaperPillButton(
                    title: "全量快照与灾备 (\(serverBackups.count)/7)",
                    isSelected: backupSubTab == "backup"
                ) {
                    backupSubTab = "backup"
                }

                PaperPillButton(
                    title: "对象存储设置 (R2/S3)",
                    isSelected: backupSubTab == "storage"
                ) {
                    backupSubTab = "storage"
                }

                Spacer()
            }
            .padding(.bottom, 2)

            switch backupSubTab {
            case "backup":
                serverBackupSubView
            case "storage":
                objectStorageSubView
            default:
                serverBackupSubView
            }
        }
        .task {
            if appState.isPaired {
                await loadServerBackups()
                await loadStorageStatusAction()
            }
        }
    }
    private var serverBackupSubView: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
            // 顶栏缓存体量与全量快照触发
            HStack {
                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                    HStack(spacing: ArchiveSpacing.s) {
                        Text("中枢系统级全量热备")
                            .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Text("\(serverBackups.count)/7 份")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                    }
                    Text("本地缓存：散页 \(appState.entries.count) 篇 · 账目 \(appState.transactions.count) 笔 · 待发 \(appState.outboxItems.count) 项 · 目的地：\(storageStatus?.configured == true ? "Cloudflare R2" : "中枢本地磁盘")")
                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }

                Spacer()

                HStack(spacing: ArchiveSpacing.s) {
                    Button {
                        Task { @MainActor in
                            await loadServerBackups()
                        }
                    } label: {
                        HStack(spacing: ArchiveSpacing.xs) {
                            if isLoadingServerBackups {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                            }
                            Text("刷新")
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()

                    Button {
                        createServerBackupAction()
                    } label: {
                        HStack(spacing: ArchiveSpacing.xs) {
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
                    .paperButtonFocusRing()
                    .disabled(isCreatingServerBackup || !appState.isPaired)
                }
            }

            // 极简备份策略说明
            Text("每日自动热备整库，保留最新 7 份快照，支持 Cloudflare R2 与本地存储双重冗余，可在任一时间节点一键回滚整库。")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                .foregroundStyle(ArchivePalette.inkSecondary)
                .padding(ArchiveSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))

            // 快照操作反馈（成功 / 失败）统一以 banner 呈现
            settingsFeedbackBanner(feedback: backupActionFeedback, error: backupActionError)

            // 历史快照清单
            Text("历史快照归档清单 (\(serverBackups.count)/7)")
                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                .foregroundStyle(ArchivePalette.inkPrimary)

            if isLoadingServerBackups && serverBackups.isEmpty {
                ProgressView().padding(.vertical, ArchiveSpacing.m)
            } else if serverBackups.isEmpty {
                Text("暂无中枢备份快照，您可以点击右上角「立即生成快照」创建首个全量热备。")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .padding(.vertical, ArchiveSpacing.m)
            } else {
                VStack(spacing: ArchiveSpacing.s) {
                    ForEach(serverBackups) { backup in
                        HStack(spacing: ArchiveSpacing.s) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 13))
                                .foregroundStyle(ArchivePalette.accentMoss)

                            VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                HStack(spacing: ArchiveSpacing.s) {
                                    Text("\(backup.formattedDate) 快照")
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                    Text(backup.storageTypeBadge)
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .padding(.horizontal, ArchiveSpacing.xs)
                                        .padding(.vertical, 1)
                                        .background(ArchivePalette.archivePaper)
                                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                }
                                Text("\(backup.formattedSize) · \(backup.filename)")
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                    .foregroundStyle(ArchivePalette.inkMuted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                downloadServerBackupAction(backup)
                            } label: {
                                HStack(spacing: ArchiveSpacing.xs) {
                                    Image(systemName: "arrow.down.to.line")
                                        .font(.system(size: 10))
                                        .accessibilityHidden(true)
                                    Text("下载至 Mac")
                                }
                            }
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .paperButtonFocusRing()

                            Button {
                                appState.askConfirm(
                                    title: "确认回滚还原整库？",
                                    message: "将从快照「\(backup.filename)」恢复中枢数据库与媒体文件，现有未同步数据将被该快照覆盖。",
                                    confirmText: "确认回滚覆盖",
                                    danger: true
                                ) {
                                    restoreServerBackupAction(backup)
                                }
                            } label: {
                                HStack(spacing: ArchiveSpacing.xs) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 10))
                                        .accessibilityHidden(true)
                                    Text("回滚还原")
                                }
                            }
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                            .paperButtonFocusRing()

                            // 删除快照：图标按钮 + 无障碍标签
                            PaperIconButton(
                                systemName: "trash",
                                label: "删除快照「\(backup.filename)」",
                                help: "删除该快照",
                                size: 10,
                                tint: ArchivePalette.inkMuted
                            ) {
                                appState.askConfirm(
                                    title: "确认从中枢删除该备份快照？",
                                    message: "删除后将从中枢永久移除该备份文件，无法再回滚至此时间节点。",
                                    confirmText: "删除快照",
                                    danger: true
                                ) {
                                    deleteServerBackupAction(backup)
                                }
                            }
                        }
                        .padding(ArchiveSpacing.s)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveCardMetrics.radius))
                    }
                }
            }
        }
    }


    private var objectStorageSubView: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.l) {
            // 状态概览卡片
            HStack(spacing: ArchiveSpacing.m) {
                HStack(spacing: ArchiveSpacing.s) {
                    Image(systemName: storageStatus?.configured == true ? "cloud.fill" : "internaldrive")
                        .foregroundStyle(storageStatus?.configured == true ? ArchivePalette.accentMoss : ArchivePalette.accentWarm)
                        .font(.system(size: 14))

                    Text(storageStatus?.configured == true ? "当前接入：\(storageStatus?.provider ?? "Cloudflare R2") (已挂载)" : "当前接入：中枢本地磁盘存储 (/media)")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                Text("·")
                    .foregroundStyle(ArchivePalette.inkMuted)

                Text("媒体文件 \(storageStatus?.localFileCount ?? 0) 件 (\(formatByteCount(storageStatus?.localTotalBytes ?? 0)))")
                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                    .foregroundStyle(ArchivePalette.inkSecondary)

                Spacer()

                if storageStatus?.configured == true {
                    Button {
                        migrateStorageAction()
                    } label: {
                        HStack(spacing: ArchiveSpacing.xs) {
                            if isMigratingStorage {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                            }
                            Text(isMigratingStorage ? "正在同步…" : "双向同步媒体")
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                    .disabled(isMigratingStorage)
                }
            }
            .padding(ArchiveSpacing.m)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))

            // 模式切换与凭据表单卡片
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                HStack {
                    Text("对象存储接入凭据")
                        .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.heading, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    Spacer()

                    HStack(spacing: ArchiveSpacing.xxs) {
                        Button("Cloudflare R2") {
                            storageProviderType = "r2"
                        }
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: storageProviderType == "r2" ? .semibold : .regular))
                        .padding(.horizontal, ArchiveSpacing.s)
                        .padding(.vertical, ArchiveSpacing.xs)
                        .background(storageProviderType == "r2" ? ArchivePalette.inkPrimary : Color.clear)
                        .foregroundStyle(storageProviderType == "r2" ? ArchivePalette.archivePaper : ArchivePalette.inkSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                        .buttonStyle(.plain)

                        Button("S3 兼容协议") {
                            storageProviderType = "s3"
                        }
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: storageProviderType == "s3" ? .semibold : .regular))
                        .padding(.horizontal, ArchiveSpacing.s)
                        .padding(.vertical, ArchiveSpacing.xs)
                        .background(storageProviderType == "s3" ? ArchivePalette.inkPrimary : Color.clear)
                        .foregroundStyle(storageProviderType == "s3" ? ArchivePalette.archivePaper : ArchivePalette.inkSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                        .buttonStyle(.plain)
                    }
                    .padding(ArchiveSpacing.xxs)
                    .background(ArchivePalette.archivePaper)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
                    .overlay(RoundedRectangle(cornerRadius: ArchiveRadius.sm).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                }

                // 表单网格
                Grid(alignment: .leading, horizontalSpacing: ArchiveSpacing.l, verticalSpacing: ArchiveSpacing.s) {
                    GridRow {
                        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                            Text(storageProviderType == "r2" ? "Cloudflare 账户 ID *" : "S3 服务端点 (Endpoint) *")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                            TextField(
                                storageProviderType == "r2" ? "32 位 Cloudflare Account ID" : "https://s3.ap-northeast-1.amazonaws.com",
                                text: storageProviderType == "r2" ? $storageAccountId : $storageEndpoint
                            )
                            .textFieldStyle(.plain)
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                            .padding(ArchiveSpacing.s)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(RoundedRectangle(cornerRadius: ArchiveRadius.xs).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }

                        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                            Text("存储桶名称 (Bucket Name) *")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                            TextField("looseleaf-bucket", text: $storageBucketName)
                                .accessibilityLabel("存储桶名称")
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                                .padding(ArchiveSpacing.s)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                .overlay(RoundedRectangle(cornerRadius: ArchiveRadius.xs).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }
                    }

                    GridRow {
                        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                            Text("访问密钥 ID (Access Key ID) *")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                            TextField("Access Key ID", text: $storageAccessKeyId)
                                .accessibilityLabel("访问密钥 ID")
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                                .padding(ArchiveSpacing.s)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                .overlay(RoundedRectangle(cornerRadius: ArchiveRadius.xs).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }

                        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                            HStack {
                                Text("私有访问密钥 (Secret Access Key)")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                    .foregroundStyle(ArchivePalette.inkSecondary)
                                if storageStatus?.hasSecretKey == true {
                                    Text("已配置")
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                        .foregroundStyle(ArchivePalette.accentMoss)
                                }
                            }

                            HStack(spacing: ArchiveSpacing.xs) {
                                if showSecretKey {
                                    TextField(storageStatus?.hasSecretKey == true ? "留空保持已存密钥" : "Secret Access Key", text: $storageSecretAccessKey)
                                        .textFieldStyle(.plain)
                                } else {
                                    SecureField(storageStatus?.hasSecretKey == true ? "留空保持已存密钥" : "Secret Access Key", text: $storageSecretAccessKey)
                                        .textFieldStyle(.plain)
                                }

                                // 密钥显隐切换：命中区不小于 ArchiveHitTarget.minPointer，VoiceOver 可朗读
                                PaperIconButton(
                                    systemName: showSecretKey ? "eye.slash" : "eye",
                                    label: showSecretKey ? "隐藏私有访问密钥" : "显示私有访问密钥",
                                    help: showSecretKey ? "隐藏私有访问密钥" : "显示私有访问密钥",
                                    size: 11,
                                    tint: ArchivePalette.inkMuted
                                ) {
                                    showSecretKey.toggle()
                                }
                            }
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                            .padding(ArchiveSpacing.s)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(RoundedRectangle(cornerRadius: ArchiveRadius.xs).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }
                    }

                    GridRow {
                        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                            Text("公网访问加速域名 (可选)")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkSecondary)
                            TextField("https://media.example.com", text: $storagePublicDomain)
                                .accessibilityLabel("公开访问域名")
                                .textFieldStyle(.plain)
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.body))
                                .padding(ArchiveSpacing.s)
                                .background(ArchivePalette.archivePaper)
                                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                .overlay(RoundedRectangle(cornerRadius: ArchiveRadius.xs).stroke(ArchivePalette.borderSubtle, lineWidth: 0.5))
                        }

                        VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                            Text("临时下载链接有效时长")
                                .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                .foregroundStyle(ArchivePalette.inkSecondary)

                            let presignOptions: [PaperSelectOption<Int>] = [
                                PaperSelectOption(value: 900, label: "15 分钟 (高安全)"),
                                PaperSelectOption(value: 1800, label: "30 分钟 (推荐)"),
                                PaperSelectOption(value: 3600, label: "1 小时"),
                                PaperSelectOption(value: 21600, label: "6 小时"),
                                PaperSelectOption(value: 86400, label: "24 小时"),
                                PaperSelectOption(value: 604800, label: "7 天 (最长上限)")
                            ]
                            PaperSelect(selection: $storagePresignSeconds, options: presignOptions)
                        }
                    }
                }

                // 提示与反馈信息
                settingsFeedbackBanner(feedback: storageFeedback, error: storageError)

                Divider().overlay(ArchivePalette.borderSubtle.opacity(0.6)).padding(.vertical, ArchiveSpacing.xs)

                // 操作按钮栏
                HStack {
                    if storageStatus?.configured == true {
                        Button {
                            appState.askConfirm(
                                title: "切换为本地磁盘存储",
                                message: "确定要关闭云端对象存储并恢复为本地磁盘存储模式吗？新上传的文件将直接保存在服务端本地磁盘 (/media)。",
                                confirmText: "确认恢复本地存储",
                                danger: true
                            ) {
                                resetStorageAction()
                            }
                        } label: {
                            HStack(spacing: ArchiveSpacing.xs) {
                                if isResettingStorage {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 10))
                                }
                                Text(isResettingStorage ? "正在切换…" : "恢复为本地磁盘存储")
                            }
                        }
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .buttonStyle(.plain)
                        .disabled(isResettingStorage || isSavingStorage || isTestingStorage)
                    }

                    Spacer()

                    Button {
                        testStorageAction()
                    } label: {
                        HStack(spacing: ArchiveSpacing.xs) {
                            if isTestingStorage {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10))
                            }
                            Text(isTestingStorage ? "握手测试中…" : "测试连通性")
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                    .disabled(isTestingStorage || isSavingStorage)

                    Button {
                        saveStorageAction()
                    } label: {
                        HStack(spacing: ArchiveSpacing.xs) {
                            if isSavingStorage {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            Text(isSavingStorage ? "保存中…" : "保存并挂载配置")
                        }
                    }
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    .paperButtonFocusRing()
                    .disabled(isSavingStorage || isTestingStorage)
                }
            }
            .padding(ArchiveCardMetrics.padding)
            .background(ArchivePalette.archiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
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
                    // 下载完成后直接提供「在访达中显示」，用户无需再去手动翻目录
                    NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                    backupActionFeedback = "已成功下载「\(item.filename)」至本地，并在访达中选中"
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
                await appState.refreshAll(forceFull: true)
                await loadServerBackups()
            } catch {
                backupActionError = "回滚还原失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 云端对象存储灾备动作 (Storage Management Actions)

    /// 字节数格式化（本文件内的统一实现，供存储用量/备份大小展示）。
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
        if storageSecretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           storageStatus?.hasSecretKey == true {
            storageError = "连通性测试需要重新输入 Secret Access Key（已保存的密钥不会回传；保存配置时可留空保持不变）"
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
        Task { @MainActor in
            defer { isMigratingStorage = false }
            do {
                let res = try await APIClient.shared.migrateStorageMedia()
                let summary = "双向增量同步完成：上传 \(res.uploadedToR2 ?? 0) 项，拉取 \(res.downloadedToLocal ?? 0) 项"
                storageFeedback = summary
                await loadStorageStatusAction()
            } catch {
                storageError = "增量同步失败: \(error.localizedDescription)"
            }
        }
    }
}
