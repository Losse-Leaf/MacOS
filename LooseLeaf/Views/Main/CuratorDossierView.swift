import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 主理人生活手记与器物图鉴视图 (CuratorDossierView)
/// 严格遵守：100% 由 GET /api/v1/profile 动态驱动，严禁硬编码姓名或城市
@MainActor
public struct CuratorDossierView: View {
    @Bindable var appState: AppState

    @State private var showEditProfileSheet: Bool = false
    @State private var selectedHeatmapDate: String? = nil

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        let prof = appState.profile

        ScrollView {
            LazyVStack(alignment: .leading, spacing: ArchiveSpacing.xl) {
                // 1. 主理人名片与暗房肖像
                profileCard(prof)

                // 1.5 生活刻度核心指标大盘
                statsOverviewGrid

                // 2. 生活刻度 · 编年时间日历图与年度卷宗
                VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                    LifeCalendarChartView(
                        entryCounts: appState.entryCountsByDate,
                        totalCount: appState.entries.count,
                        selectedDate: $selectedHeatmapDate
                    )

                    if let dateKey = selectedHeatmapDate {
                        dayEntriesDrawer(dateKey: dateKey)
                    }
                }
                .padding(18)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
            }
            .padding(ArchiveSpacing.xl)
        }
        .sheet(isPresented: $showEditProfileSheet) {
            EditCuratorProfileSheet(appState: appState) {
                showEditProfileSheet = false
            }
        }
    }

    // MARK: - 1. 主理人名片

    private func profileCard(_ prof: CuratorProfile) -> some View {
        HStack(alignment: .top, spacing: 20) {
            if !prof.avatarUrl.isEmpty, let url = APIClient.shared.resolveMediaURL(prof.avatarUrl) {
                FilmFrameView(
                    imageURL: url,
                    originalURL: url,
                    caption: "银盐肖像",
                    metaText: prof.displayCity.isEmpty ? nil : prof.displayCity,
                    maxHeight: 180
                )
                .frame(width: 180)
            }

            VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                HStack {
                    Text(prof.name.isEmpty ? "主理人档案待填写" : prof.name)
                        .font(ArchiveTypography.editorialSerif(size: 22, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)

                    if !prof.title.isEmpty {
                        Text(prof.title)
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .padding(.horizontal, ArchiveSpacing.s)
                            .padding(.vertical, 3)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                    }

                    Spacer()

                    Button("修订档案") {
                        showEditProfileSheet = true
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                }

                if !prof.displayCity.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "location")
                            .font(.system(size: 11))
                        let coordText: String = {
                            if !prof.location.isEmpty && !prof.currentCity.isEmpty && prof.location != prof.currentCity {
                                return "常居：\(prof.location) · 当下：\(prof.currentCity)"
                            } else if !prof.currentCity.isEmpty {
                                return "当下坐标：\(prof.currentCity)"
                            } else {
                                return "常居坐标：\(prof.location)"
                            }
                        }()
                        Text(coordText)
                            .font(ArchiveTypography.monoScale(size: 11.5))
                    }
                    .foregroundStyle(ArchivePalette.inkMuted)
                }

                if !prof.motto.isEmpty {
                    Text("“\(prof.motto)”")
                        .font(ArchiveTypography.editorialSerif(size: 15))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .padding(.top, 2)
                }

                if !prof.bio.isEmpty {
                    EditorialProseTextView(
                        prof.bio,
                        font: ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading),
                        color: ArchivePalette.inkSecondary,
                        lineSpacing: 3
                    )
                }

                if !prof.manifesto.isEmpty {
                    EditorialProseTextView(
                        prof.manifesto,
                        font: ArchiveTypography.bodySans(size: 12.5),
                        color: ArchivePalette.inkMuted,
                        lineSpacing: 3
                    )
                    .padding(.top, 4)
                }
            }
        }
        .padding(18)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 1.5 生活刻度核心指标大盘

    private var statsOverviewGrid: some View {
        let entriesCount = appState.stats.totalEntries > 0 ? appState.stats.totalEntries : appState.entries.count
        let photosCount = appState.stats.totalPhotos > 0 ? appState.stats.totalPhotos : appState.entries.reduce(0) { $0 + $1.attachments.count }
        let projectsCount = appState.stats.totalProjects > 0 ? appState.stats.totalProjects : appState.projects.count
        let expenseCents = appState.stats.monthExpense > 0 ? appState.stats.monthExpense : appState.transactionSummary.totalExpense

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: ArchiveSpacing.m)], spacing: ArchiveSpacing.m) {
            statMetricCard(
                title: "生活印记",
                value: "\(entriesCount)",
                unit: "篇",
                accent: ArchivePalette.inkPrimary
            )
            statMetricCard(
                title: "胶卷相片",
                value: "\(photosCount)",
                unit: "张",
                accent: ArchivePalette.accentMoss
            )
            statMetricCard(
                title: "造物项目",
                value: "\(projectsCount)",
                unit: "件",
                accent: ArchivePalette.categoryColor(for: "学习")
            )
            statMetricCard(
                title: "本月支出",
                value: FormatUtils.formattedYuan(cents: expenseCents, includeSymbol: true),
                unit: "",
                accent: ArchivePalette.accentWarm
            )
        }
    }

    private func statMetricCard(title: String, value: String, unit: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ArchiveTypography.bodySans(size: 11.5))
                .foregroundStyle(ArchivePalette.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(ArchiveTypography.monoScale(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                if !unit.isEmpty {
                    Text(unit)
                        .font(ArchiveTypography.editorialSerif(size: 11.5))
                        .foregroundStyle(ArchivePalette.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ArchiveSpacing.m)
        .background(ArchivePalette.archiveSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: ArchiveRadius.sm)
                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - 当日手记速览抽屉

    private func dayEntriesDrawer(dateKey: String) -> some View {
        let selectedDateEntries = appState.entriesByDateKey[dateKey] ?? []

        return LazyVStack(alignment: .leading, spacing: 10) {
            Divider().overlay(ArchivePalette.borderSubtle)

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(ArchivePalette.accentWarm)
                    Text("\(dateKey) 当日记录 (\(selectedDateEntries.count) 条)")
                        .font(ArchiveTypography.monoScale(size: 11.5, weight: .medium))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                Spacer()

                Button {
                    selectedHeatmapDate = nil
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: ArchiveIcon.close.systemName)
                            .font(.system(size: 10, weight: .bold))
                        Text("关闭速览")
                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    }
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
            }

            if selectedDateEntries.isEmpty {
                Text("该日未留下公开或私密手记。")
                    .font(ArchiveTypography.editorialSerif(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: ArchiveSpacing.s) {
                    ForEach(selectedDateEntries) { item in
                        Button {
                            appState.highlightedEntry = item
                        } label: {
                            VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                                HStack(spacing: 4) {
                                    Text(item.title.isEmpty ? "无题散页" : item.title)
                                        .font(ArchiveTypography.editorialSerif(size: 12.5, weight: .medium))
                                        .foregroundStyle(ArchivePalette.inkPrimary)
                                        .lineLimit(1)
                                    if item.isPrivate {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                            .accessibilityLabel("私密散页")
                                    }
                                    Spacer()
                                    Text(item.parsedDate.time)
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                }

                                if !item.content.isEmpty {
                                    Text(item.content)
                                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(10)
                            .background(ArchivePalette.archivePaper)
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchiveRadius.xs)
                                    .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .paperHover()
                        .paperButtonFocusRing(cornerRadius: ArchiveRadius.xs)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - 独立隔离的主理人档案修订弹窗 (EditCuratorProfileSheet)
/// 隔离编辑输入状态，避免在弹窗内每次敲击字符导致父级 `CuratorDossierView` 与 365 格编年热力图整树重求值。
@MainActor
struct EditCuratorProfileSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var editName: String
    @State private var editTitle: String
    @State private var editCity: String
    @State private var editLocation: String
    @State private var editMotto: String
    @State private var editBio: String
    @State private var editManifesto: String
    @State private var newAvatarKey: String?
    @State private var isUploadingAvatar: Bool = false
    @State private var isSavingProfile: Bool = false
    @State private var avatarPreviewImage: NSImage?
    @State private var dossierError: String?
    @FocusState private var isNameFocused: Bool

    init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
        let prof = appState.profile
        _editName = State(initialValue: prof.name)
        _editTitle = State(initialValue: prof.title)
        _editCity = State(initialValue: prof.currentCity)
        _editLocation = State(initialValue: prof.location)
        _editMotto = State(initialValue: prof.motto)
        _editBio = State(initialValue: prof.bio)
        _editManifesto = State(initialValue: prof.manifesto)
    }

    var body: some View {
        PaperSheetScaffold(
            title: "修订主理人档案",
            width: ArchiveSheetWidth.standard,
            isSubmitting: isSavingProfile,
            isSubmitDisabled: isUploadingAvatar,
            submitTitle: "保存档案 ⌘↩",
            onCancel: onDismiss,
            onSubmit: saveProfile
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: ArchiveSpacing.m) {
                    if let avatarPreviewImage {
                        Image(nsImage: avatarPreviewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(ArchivePalette.borderSubtle, lineWidth: 1))
                    }
                    Button {
                        selectAndUploadAvatar()
                    } label: {
                        HStack(spacing: ArchiveSpacing.xs) {
                            Image(systemName: "photo")
                            Text(isUploadingAvatar ? "正在上传肖像…" : "更换肖像照片…")
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    .paperButtonFocusRing()
                    .disabled(isUploadingAvatar)

                    if newAvatarKey != nil {
                        Text("新肖像已就绪")
                            .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                            .foregroundStyle(ArchivePalette.accentMoss)
                    }
                }
                .padding(.vertical, ArchiveSpacing.xxs)

                VStack(alignment: .leading, spacing: 4) {
                    Text("主理人称谓")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    TextField("主理人称谓", text: $editName)
                        .accessibilityLabel("主理人称谓")
                        .textFieldStyle(.plain)
                        .focused($isNameFocused)
                        .padding(ArchiveSpacing.s)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("主理人身份")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    TextField("主理人身份", text: $editTitle)
                        .accessibilityLabel("主理人身份")
                        .textFieldStyle(.plain)
                        .padding(ArchiveSpacing.s)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                HStack(spacing: ArchiveSpacing.s) {
                    PaperCityPicker(
                        selectedCode: .constant(""),
                        selectedName: $editCity,
                        placeholder: "点选当前城市…",
                        label: "当前城市",
                        isFullWidth: true
                    )

                    PaperCityPicker(
                        selectedCode: .constant(""),
                        selectedName: $editLocation,
                        placeholder: "点选常居城市…",
                        label: "常居城市",
                        isFullWidth: true
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("近况题记")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    TextField("近况题记", text: $editMotto)
                        .accessibilityLabel("近况题记")
                        .textFieldStyle(.plain)
                        .padding(ArchiveSpacing.s)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("副标题（生活简介）")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    TextField("副标题", text: $editBio, axis: .vertical)
                        .accessibilityLabel("副标题")
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .padding(ArchiveSpacing.s)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("主理人宣言")
                        .font(ArchiveTypography.monoScale(size: 11))
                        .foregroundStyle(ArchivePalette.inkMuted)
                    TextField("主理人宣言", text: $editManifesto, axis: .vertical)
                        .accessibilityLabel("主理人宣言")
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .padding(ArchiveSpacing.s)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                }

                if let dossierError {
                    Text(dossierError)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
            }
        }
        .onAppear {
            isNameFocused = true
        }
    }

    private func saveProfile() {
        guard !isSavingProfile, !isUploadingAvatar else { return }
        isSavingProfile = true
        Task { @MainActor in
            defer { isSavingProfile = false }
            let trimmedCity = editCity.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLoc = editLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            let req = UpdateProfileRequest(
                name: editName,
                title: editTitle,
                bio: editBio,
                location: trimmedLoc,
                currentCity: trimmedCity,
                avatarKey: newAvatarKey ?? appState.profile.avatarKey,
                motto: editMotto,
                manifesto: editManifesto
            )
            do {
                _ = try await APIClient.shared.updateCuratorProfile(req)
                await appState.loadConfigAndProfile()
                onDismiss()
            } catch {
                dossierError = "档案保存失败：\(error.localizedDescription)"
            }
        }
    }

    private func selectAndUploadAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let handleSelection: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                isUploadingAvatar = true
                defer { isUploadingAvatar = false }
                do {
                    let processed = try await SandboxFileAccess.withAccess(to: url) { scopedURL in
                        try await ImageProcessor.processImageFileInBackground(
                            at: scopedURL,
                            maxPixelSize: 1024,
                            quality: 0.85
                        )
                    }
                    avatarPreviewImage = NSImage(data: processed.compressedData)
                    let att = try await APIClient.shared.uploadUnifiedMultipart(
                        fileData: processed.compressedData,
                        filename: "avatar-\(Int(Date().timeIntervalSince1970)).jpg",
                        mimeType: "image/jpeg",
                        folder: "avatar"
                    )
                    newAvatarKey = att.objectKey
                } catch {
                    dossierError = "肖像上传失败：\(error.localizedDescription)"
                }
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: handleSelection)
        } else {
            panel.begin(completionHandler: handleSelection)
        }
    }
}

#if DEBUG
#Preview("主理人档案") {
    CuratorDossierView(appState: ArchivePreviewFixtures.makeAppState())
        .frame(width: 1100, height: 760)
}
#endif
