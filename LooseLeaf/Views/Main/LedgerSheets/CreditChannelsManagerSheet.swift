import SwiftUI

/// 信贷与分期渠道管理弹窗 (CreditChannelsManagerSheet)
/// 从 LedgerAssetsView 中拆出的独立 Sheet 组件：
/// 负责信贷渠道（花呗 / 白条 / 自定义信用卡）的增删改与每月固定还款日配置。
/// 仅做文件拆分，逻辑、数值与视觉表现与拆分前完全一致。

// MARK: - 独立弹窗组件：信贷与分期渠道管理 (CreditChannelsManagerSheet)

@MainActor
public struct CreditChannelsManagerSheet: View {
    @Bindable var appState: AppState
    var onDismiss: () -> Void

    @State private var newName: String = ""
    @State private var newCode: String = ""
    @State private var newRepaymentDay: Int = 10
    @State private var editingChannelId: Int?
    @State private var editName: String = ""
    @State private var editRepaymentDay: Int = 10
    @State private var isSubmitting: Bool = false
    @State private var errorText: String?

    private var channels: [CreditChannel] {
        if !appState.creditChannels.isEmpty {
            return appState.creditChannels
        }
        return [
            CreditChannel(id: 1, code: "huabei", name: "花呗", repaymentDay: 10, isBuiltin: true),
            CreditChannel(id: 2, code: "baitiao", name: "白条", repaymentDay: 15, isBuiltin: true)
        ]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ArchiveCardMetrics.padding) {
            HStack {
                Text("信贷与分期渠道管理")
                    .font(ArchiveTypography.editorialSerif(size: ArchiveTypography.Scale.title, weight: .semibold))
                    .foregroundStyle(ArchivePalette.inkPrimary)
                Spacer()
                Button("关闭") {
                    onDismiss()
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .paperButtonFocusRing()
            }

            Text("配置常用的信用卡、花呗或白条渠道及每月固定还款日（1~31 日），记账勾选分期时将自动核算剩余期数与待还负债。")
                .font(ArchiveTypography.bodySans(size: 11.5))
                .foregroundStyle(ArchivePalette.inkSecondary)

            ScrollView {
                VStack(spacing: ArchiveSpacing.s) {
                    ForEach(channels) { ch in
                        HStack(spacing: 10) {
                            if editingChannelId == ch.id {
                                TextField("渠道名称", text: $editName)
                                    .textFieldStyle(.plain)
                                    .font(ArchiveTypography.bodySans(size: 12.5))
                                    .padding(6)
                                    .background(ArchivePalette.archivePaper)
                                    .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                                    .frame(width: 120)

                                PaperSelect(
                                    selection: $editRepaymentDay,
                                    options: (1...31).map { PaperSelectOption(value: $0, label: "每月 \($0) 日") },
                                    label: "还款日："
                                )

                                Spacer()

                                Button("保存") {
                                    saveChannelEdit(ch)
                                }
                                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                                .paperButtonFocusRing()
                                .disabled(isSubmitting || editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button("取消") {
                                    editingChannelId = nil
                                }
                                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                                .paperButtonFocusRing()
                            } else {
                                VStack(alignment: .leading, spacing: ArchiveSpacing.xxs) {
                                    HStack(spacing: 6) {
                                        Text(ch.name)
                                            .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.heading, weight: .medium))
                                            .foregroundStyle(ArchivePalette.inkPrimary)
                                        Text(ch.code)
                                            .font(ArchiveTypography.monoScale(size: 10.5))
                                            .foregroundStyle(ArchivePalette.inkMuted)
                                        if ch.isBuiltin {
                                            Text("内置")
                                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                                .foregroundStyle(ArchivePalette.accentMoss)
                                                .padding(.horizontal, ArchiveSpacing.xs)
                                                .padding(.vertical, 1)
                                                .background(ArchivePalette.archivePaper)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
                                    Text("每月 \(ch.repaymentDay) 日还款")
                                        .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.caption))
                                        .foregroundStyle(ArchivePalette.inkSecondary)
                                }

                                Spacer()

                                PaperIconButton(
                                    systemName: "pencil",
                                    label: "修改渠道与还款日",
                                    help: "修改渠道与还款日",
                                    size: 11,
                                    tint: ArchivePalette.inkMuted
                                ) {
                                    editingChannelId = ch.id
                                    editName = ch.name
                                    editRepaymentDay = ch.repaymentDay
                                }

                                if !ch.isBuiltin {
                                    PaperIconButton(
                                        systemName: ArchiveIcon.delete.systemName,
                                        label: "删除自定义渠道",
                                        help: "删除自定义渠道",
                                        size: 11,
                                        tint: ArchivePalette.accentWarm
                                    ) {
                                        deleteChannel(ch)
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                        )
                    }
                }
            }
            .frame(maxHeight: 220)

            Divider().overlay(ArchivePalette.borderSubtle)

            // 新增自定义信贷渠道
            VStack(alignment: .leading, spacing: ArchiveSpacing.s) {
                Text("新增自定义信贷渠道")
                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body, weight: .medium))
                    .foregroundStyle(ArchivePalette.inkPrimary)

                HStack(spacing: ArchiveSpacing.s) {
                    TextField("渠道名称", text: $newName)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.body))
                        .padding(7)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))

                    TextField("代号（如 cmb）", text: $newCode)
                        .textFieldStyle(.plain)
                        .font(ArchiveTypography.monoScale(size: 11.5))
                        .padding(7)
                        .background(ArchivePalette.archiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))
                        .frame(width: 110)

                    PaperSelect(
                        selection: $newRepaymentDay,
                        options: (1...31).map { PaperSelectOption(value: $0, label: "每月 \($0) 日") },
                        label: "还款日："
                    )

                    Button("添加渠道") {
                        createChannel()
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
                    .paperButtonFocusRing()
                    .disabled(isSubmitting || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(ArchiveTypography.bodySans(size: 11.5))
                    .foregroundStyle(ArchivePalette.accentWarm)
            }
        }
        .padding(20)
        .frame(
            minWidth: ArchiveSheetWidth.standard,
            idealWidth: ArchiveSheetWidth.standard,
            maxWidth: ArchiveSheetWidth.standard
        )
        .background(ArchivePalette.archivePaper)
        .task {
            if let list = try? await APIClient.shared.fetchCreditChannels() {
                appState.creditChannels = list
            }
        }
    }

    private func createChannel() {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let cleanCode = newCode.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateCreditChannelRequest(
                    code: cleanCode.isEmpty ? nil : cleanCode,
                    name: cleanName,
                    repaymentDay: newRepaymentDay
                )
                _ = try await APIClient.shared.createCreditChannel(req)
                newName = ""
                newCode = ""
                await appState.loadTransactionsAndAssets(forceFull: false)
            } catch {
                errorText = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func saveChannelEdit(_ ch: CreditChannel) {
        let cleanName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let req = CreateCreditChannelRequest(
                    code: ch.code,
                    name: cleanName,
                    repaymentDay: editRepaymentDay,
                    color: ch.color
                )
                _ = try await APIClient.shared.updateCreditChannel(id: ch.id, req)
                editingChannelId = nil
                await appState.loadTransactionsAndAssets(forceFull: false)
            } catch {
                errorText = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func deleteChannel(_ ch: CreditChannel) {
        // 关键：破坏性操作要有二次确认。
        // 删除账目 / 手稿 / 设备 / 快照 / 吊销设备全都有确认框，
        // 唯独删渠道是「一点即删」—— 而渠道被账目分期引用
        // （installment_channel_code），误删会让既有分期账单失去渠道名。
        appState.askConfirm(
            title: "确认删除该信贷渠道？",
            message: "删除后，以此渠道记账的分期账单将失去渠道归属。",
            confirmText: "删除渠道",
            danger: true
        ) {
            performDeleteChannel(ch)
        }
    }

    private func performDeleteChannel(_ ch: CreditChannel) {
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                try await APIClient.shared.deleteCreditChannel(id: ch.id)
                await appState.loadTransactionsAndAssets(forceFull: false)
            } catch {
                errorText = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
