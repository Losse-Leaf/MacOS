import SwiftUI

/// 统一城市足迹票根新建与修订弹窗 (FootprintEditorSheet)
/// - `footprint == nil`：点亮城市行迹票根
/// - `footprint != nil`：修订既有行迹票根（省略 `attachment_ids` 保留跨端照片，取消离境日期传空串清空）
@MainActor
public struct FootprintEditorSheet: View {
    @Bindable var appState: AppState
    let footprint: Footprint?
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

    public init(appState: AppState, footprint: Footprint? = nil, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.footprint = footprint
        self.onDismiss = onDismiss
        if let footprint {
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
        } else {
            _cityCode = State(initialValue: "")
            _cityName = State(initialValue: "")
            _title = State(initialValue: "")
            _note = State(initialValue: "")
            let now = Date()
            _visitedDate = State(initialValue: now)
            _hasDepartedDate = State(initialValue: false)
            _departedDate = State(initialValue: now)
            _isPrivate = State(initialValue: false)
        }
    }

    private var isEditing: Bool { footprint != nil }

    public var body: some View {
        PaperSheetScaffold(
            title: isEditing ? "修订行迹票根" : "点亮城市行迹票根",
            subtitle: isEditing ? nil : "山川印谱 · 典藏特种纸票根",
            width: ArchiveSheetWidth.compact,
            isSubmitting: isSubmitting,
            isSubmitDisabled: cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            submitTitle: isEditing ? "保存票根修改 ⌘↩" : "镌刻票根并伴生入流 ⌘↩",
            onCancel: onDismiss,
            onSubmit: submit
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
                    .accessibilityLabel("旅程标题")
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .padding(ArchiveSpacing.s)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                TextField("行迹随笔手记…", text: $note, axis: .vertical)
                    .accessibilityLabel("行迹随笔手记")
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

    private func submit() {
        let cleanCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCity.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                if let footprint {
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
                } else {
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
                }
                await appState.refreshAfterSecondaryWrite()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
