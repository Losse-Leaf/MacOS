import SwiftUI

/// 城市足迹票根相关弹窗集合 (NewFootprintSheet / EditFootprintSheet)
/// 1. NewFootprintSheet —— 点亮城市行迹票根（行政区划 / 到访时间 / 离境日期 / 私密开关 / 标题 / 手记）
/// 2. EditFootprintSheet —— 修订既有行迹票根（保留跨端照片绑定，连带刷新伴生散页）

// MARK: - 点亮城市足迹弹窗 (NewFootprintSheet)

@MainActor
public struct NewFootprintSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var cityCode: String = ""
    @State private var cityName: String = ""
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var visitedDate: Date = Date()
    @State private var hasDepartedDate: Bool = false
    @State private var departedDate: Date = Date()
    @State private var isPrivate: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    @FocusState private var isTitleFocused: Bool

    public init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "点亮城市行迹票根",
            subtitle: "山川印谱 · 典藏特种纸票根",
            width: ArchiveSheetWidth.compact,
            isSubmitting: isSubmitting,
            isSubmitDisabled: cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            submitTitle: "镌刻票根并伴生入流 ⌘↩",
            onCancel: onDismiss,
            onSubmit: submitFootprint
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName, placeholder: "选择行政区划城市…")

                PaperDateTimePicker(selection: $visitedDate, label: "到访时间", showQuickShortcuts: true)

                VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                    Toggle("包含返程 / 离境日期（多日漫游）", isOn: $hasDepartedDate)
                        .toggleStyle(.paperCheckbox)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    if hasDepartedDate {
                        PaperDatePicker(selection: $departedDate, enableTime: false, label: "离境日期")
                    }
                }

                TextField("旅程标题", text: $title)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("行迹随笔手记…", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                HStack {
                    Label("私密行迹（仅配对主理人设备可见）", systemImage: ArchiveIcon.lock.systemName)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Spacer()
                    Toggle("私密行迹", isOn: $isPrivate)
                        .labelsHidden()
                        .toggleStyle(.paperSwitch)
                        .accessibilityLabel("设为私密行迹")
                }

                if let errorText {
                    Text(errorText)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
            }
        }
        .onAppear {
            isTitleFocused = true
        }
    }

    private func submitFootprint() {
        let cleanCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCity.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateFootprintRequest(
                    cityCode: cityCode.isEmpty ? (FormatUtils.resolveCityCode(from: cleanCity) ?? "") : cityCode,
                    cityName: cleanCity,
                    title: title.isEmpty ? nil : title,
                    visitedAt: FormatUtils.beijingISOString(from: visitedDate),
                    departedAt: hasDepartedDate ? FormatUtils.beijingDateString(from: departedDate) : nil,
                    note: note.isEmpty ? nil : note,
                    isPrivate: isPrivate
                )
                _ = try await APIClient.shared.createFootprint(req)
                await appState.refreshAfterSecondaryWrite()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - 修订足迹票根弹窗 (EditFootprintSheet)

@MainActor
public struct EditFootprintSheet: View {
    @Bindable var appState: AppState
    let footprint: Footprint
    var onDismiss: () -> Void

    @State private var cityCode: String
    @State private var cityName: String
    @State private var title: String
    @State private var note: String
    @State private var visitedDate: Date
    @State private var hasDepartedDate: Bool
    @State private var departedDate: Date
    @State private var isPrivate: Bool
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?
    @FocusState private var isTitleFocused: Bool

    public init(appState: AppState, footprint: Footprint, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.footprint = footprint
        self.onDismiss = onDismiss
        _cityCode = State(initialValue: footprint.cityCode)
        _cityName = State(initialValue: footprint.cityName)
        _title = State(initialValue: footprint.title ?? "")
        _note = State(initialValue: footprint.note ?? "")
        let parsedVisited = FormatUtils.parseFlexDate(footprint.visitedAt) ?? Date()
        _visitedDate = State(initialValue: parsedVisited)
        let rawDeparted = (footprint.departedAt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        _hasDepartedDate = State(initialValue: !rawDeparted.isEmpty)
        _departedDate = State(initialValue: FormatUtils.parseFlexDate(rawDeparted) ?? parsedVisited)
        _isPrivate = State(initialValue: footprint.isPrivate ?? false)
    }

    public var body: some View {
        PaperSheetScaffold(
            title: "修订行迹票根",
            width: ArchiveSheetWidth.compact,
            isSubmitting: isSubmitting,
            isSubmitDisabled: cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            submitTitle: "保存票根修改 ⌘↩",
            onCancel: onDismiss,
            onSubmit: updateFootprint
        ) {
            VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
                PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName)

                PaperDateTimePicker(selection: $visitedDate, label: "到访时间", showQuickShortcuts: true)

                VStack(alignment: .leading, spacing: ArchiveSpacing.xs) {
                    Toggle("包含返程 / 离境日期（多日漫游）", isOn: $hasDepartedDate)
                        .toggleStyle(.paperCheckbox)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                    if hasDepartedDate {
                        PaperDatePicker(selection: $departedDate, enableTime: false, label: "离境日期")
                    }
                }

                TextField("旅程标题", text: $title)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("随笔手记…", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                HStack {
                    Label("私密行迹（仅配对主理人设备可见）", systemImage: ArchiveIcon.lock.systemName)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                    Spacer()
                    Toggle("私密行迹", isOn: $isPrivate)
                        .labelsHidden()
                        .toggleStyle(.paperSwitch)
                        .accessibilityLabel("设为私密行迹")
                }

                if let errorText {
                    Text(errorText)
                        .font(ArchiveTypography.bodySans(size: 11.5))
                        .foregroundStyle(ArchivePalette.accentWarm)
                }
            }
        }
        .onAppear {
            isTitleFocused = true
        }
    }

    private func updateFootprint() {
        let cleanCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCity.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateFootprintRequest(
                    cityCode: cityCode.isEmpty ? (FormatUtils.resolveCityCode(from: cleanCity) ?? footprint.cityCode) : cityCode,
                    cityName: cleanCity,
                    title: title,
                    visitedAt: FormatUtils.beijingISOString(from: visitedDate),
                    departedAt: hasDepartedDate ? FormatUtils.beijingDateString(from: departedDate) : "",
                    note: note,
                    isPrivate: isPrivate
                )
                _ = try await APIClient.shared.updateFootprint(id: footprint.id, req)
                await appState.refreshAfterSecondaryWrite()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
