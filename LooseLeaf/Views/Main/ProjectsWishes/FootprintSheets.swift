import SwiftUI

/// 城市足迹票根相关弹窗集合 (NewFootprintSheet / EditFootprintSheet)
/// 从 ProjectsWishesView 中拆出的独立 Sheet 组件：
/// 1. NewFootprintSheet —— 点亮城市行迹票根（行政区划 / 到访时间 / 标题 / 手记）
/// 2. EditFootprintSheet —— 修订既有行迹票根
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

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
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            Text("点亮城市行迹票根")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName, placeholder: "选择行政区划城市…")

            PaperDateTimePicker(selection: $visitedDate, label: "到访时间", showQuickShortcuts: true)

            TextField("旅程标题", text: $title)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("行迹随笔手记", text: $note)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("镌刻票根并伴生入流") {
                    submitFootprint()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(
            minWidth: ArchiveSheetWidth.compact,
            idealWidth: ArchiveSheetWidth.compact,
            maxWidth: ArchiveSheetWidth.compact
        )
        .background(ArchivePalette.archivePaper)
    }

    private func submitFootprint() {
        let cleanCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCity.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateFootprintRequest(
                    cityCode: cityCode.isEmpty ? (FormatUtils.resolveCityCode(from: cleanCity) ?? "330100") : cityCode,
                    cityName: cleanCity,
                    title: title.isEmpty ? nil : title,
                    visitedAt: FormatUtils.beijingISOString(from: visitedDate),
                    note: note.isEmpty ? nil : note
                )
                _ = try await APIClient.shared.createFootprint(req)
                await appState.loadProjectsWishesFootprints()
                await appState.loadEntries(forceFull: true)
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
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    public init(appState: AppState, footprint: Footprint, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.footprint = footprint
        self.onDismiss = onDismiss
        _cityCode = State(initialValue: footprint.cityCode)
        _cityName = State(initialValue: footprint.cityName)
        _title = State(initialValue: footprint.title ?? "")
        _note = State(initialValue: footprint.note ?? "")
        _visitedDate = State(initialValue: FormatUtils.parseFlexDate(footprint.visitedAt) ?? Date())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveSpacing.m) {
            Text("修订行迹票根")
                .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                .foregroundStyle(ArchivePalette.inkPrimary)

            PaperCityPicker(selectedCode: $cityCode, selectedName: $cityName)

            PaperDateTimePicker(selection: $visitedDate, label: "到访时间", showQuickShortcuts: true)

            TextField("旅程标题", text: $title)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            TextField("随笔手记", text: $note)
                .textFieldStyle(.plain)
                .padding(ArchiveSpacing.s)
                .background(ArchivePalette.archiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }

            HStack {
                Button("取消") { onDismiss() }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                Spacer()
                Button("保存票根修改") {
                    updateFootprint()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                .disabled(cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(
            minWidth: ArchiveSheetWidth.compact,
            idealWidth: ArchiveSheetWidth.compact,
            maxWidth: ArchiveSheetWidth.compact
        )
        .background(ArchivePalette.archivePaper)
    }

    private func updateFootprint() {
        let cleanCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCity.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateFootprintRequest(
                    cityCode: cityCode.isEmpty ? (FormatUtils.resolveCityCode(from: cleanCity) ?? footprint.cityCode) : cityCode,
                    cityName: cleanCity,
                    title: title.isEmpty ? nil : title,
                    visitedAt: FormatUtils.beijingISOString(from: visitedDate),
                    note: note.isEmpty ? nil : note
                )
                _ = try await APIClient.shared.updateFootprint(id: footprint.id, req)
                await appState.loadProjectsWishesFootprints()
                onDismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
