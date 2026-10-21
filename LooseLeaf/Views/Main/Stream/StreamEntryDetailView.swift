import SwiftUI
import AppKit

    /// 散页详情视图 (Entry Detail)
/// 从 StreamView 拆出：既用于主窗口内的详情弹层，也用于「在新窗口打开」的独立详情窗口。
struct StreamEntryDetailView: View {
    let entry: LifeEntry
    let appState: AppState
    /// 编辑该条手稿
    var onEditEntry: (LifeEntry) -> Void = { _ in }
    /// 编辑该笔账目
    var onEditTransaction: (Transaction) -> Void = { _ in }
    /// 删除该笔账目
    var onDeleteTransaction: (Transaction) -> Void = { _ in }

    var body: some View {
        let isTx = (entry.type == "transaction")
        // 账目 id 可能是合成的负数（由账目派生的伴生条目），因此先归一到 Int
        let txId = Int(entry.associatedTransactionId ?? Int64(entry.id))
        let matchingTx = isTx ? appState.transactionById[txId] : nil
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Self.entryTypeBadge(entry.type))
                    .font(ArchiveTypography.monoScale(size: 11))
                    .foregroundStyle(ArchivePalette.accentWarm)
                Text(entry.parsedDate.dotDateTime)
                    .font(ArchiveTypography.monoScale(size: 11.5))
                    .foregroundStyle(ArchivePalette.inkMuted)
                Spacer()
                if appState.isPaired && (entry.id > 0 || (isTx && matchingTx != nil)) {
                    if isTx {
                        if let tx = matchingTx {
                            Button("编辑账目") {
                                appState.highlightedEntry = nil
                                onEditTransaction(tx)
                            }
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .buttonStyle(.plain)

                            Button("删除账目") {
                                appState.askConfirm(
                                    title: ArchiveSharedCopy.transactionDeleteTitle,
                                    message: ArchiveSharedCopy.transactionDeleteMessage,
                                confirmText: ArchiveSharedCopy.transactionDeleteConfirmText,
                                    danger: true
                                ) {
                                    onDeleteTransaction(tx)
                                    appState.highlightedEntry = nil
                                }
                            }
                            .font(ArchiveTypography.bodySans(size: 12))
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button("编辑手稿") {
                            let target = entry
                            appState.highlightedEntry = nil
                            onEditEntry(target)
                        }
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.inkSecondary)
                        .buttonStyle(.plain)

                        Button("删除记录") {
                            // 统一走 AppState 的删除入口。
                            // 关键：原先这里自己 `try? await APIClient.deleteEntry` ——
                            // 失败被静默吞掉、界面照常关闭、条目留在原地，
                            // 而且没有 ⌘Z 撤销、没有错误横幅。
                            // 时间流卡片走的是 AppState.deleteEntryAction（横幅 + 撤销栈），
                            // 同一操作两套实现，体验不一致。
                            appState.askConfirm(
                                title: ArchiveSharedCopy.entryDeleteTitle,
                                message: ArchiveSharedCopy.entryDeleteMessage,
                                confirmText: ArchiveSharedCopy.entryDeleteConfirmText,
                                danger: true
                            ) {
                                appState.highlightedEntry = nil
                                appState.deleteEntryAction(entry)
                            }
                        }
                        .font(ArchiveTypography.bodySans(size: 12))
                        .foregroundStyle(ArchivePalette.accentWarm)
                        .buttonStyle(.plain)
                    }
                }
                Button("关闭") {
                    appState.highlightedEntry = nil
                }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
            }

            if let tx = matchingTx {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tx.title.isEmpty ? tx.category : tx.title)
                            .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                        Spacer()
                        Text("\(tx.type == "income" ? "+" : "-")\(FormatUtils.formattedYuan(cents: tx.amount, includeSymbol: true))")
                            .font(ArchiveTypography.monoScale(size: 22, weight: .bold))
                            .foregroundStyle(tx.type == "income" ? ArchivePalette.accentMoss : ArchivePalette.inkPrimary)
                    }

                    HStack(spacing: 8) {
                        Text(tx.category)
                            .font(ArchiveTypography.bodySans(size: 11.5))
                            .foregroundStyle(ArchivePalette.inkSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(ArchivePalette.archiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        if let pay = tx.paymentMethod, !pay.isEmpty {
                            Text(pay)
                                .font(ArchiveTypography.bodySans(size: 11.5))
                                .foregroundStyle(ArchivePalette.inkMuted)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(ArchivePalette.archiveSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        if tx.isInstallment == true, let months = tx.installmentMonths, months > 0 {
                            Text("分期 \(months) 期")
                                .font(ArchiveTypography.monoScale(size: 11))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(ArchivePalette.accentWarm, lineWidth: 0.5)
                                )
                        }
                    }

                    if let note = tx.note, !note.isEmpty {
                        Text(note)
                            .font(ArchiveTypography.bodySans(size: 13.5))
                            .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.88))
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 8) {
                    if let city = entry.cityName ?? entry.location, !city.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10))
                            Text(city)
                                .font(ArchiveTypography.monoScale(size: 11))
                        }
                        .foregroundStyle(ArchivePalette.inkMuted)
                    }
                }

                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(ArchiveTypography.editorialSerif(size: 20, weight: .semibold))
                        .foregroundStyle(ArchivePalette.inkPrimary)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(LocalizedStringKey(entry.content))
                            .font(ArchiveTypography.bodySans(size: 14))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        if !entry.attachments.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(entry.attachments) { att in
                                        // 同时间流：详情页也用缩略图，
                                        // 点开灯箱时才去拉原图。
                                        let displayURL = att.thumbnailUrl ?? att.url
                                        if let url = APIClient.shared.resolveMediaURL(displayURL) {
                                            FilmFrameView(
                                                imageURL: url,
                                                caption: entry.title.isEmpty ? att.originalFilename : entry.title,
                                                metaText: entry.parsedDate.dotDate,
                                                maxHeight: 200
                                            ) {
                                                appState.lightboxAttachment = att
                                            } onExportNotice: { message in
                                                appState.showTemporaryBanner(message)
                                            }
                                            .frame(width: 240)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 420)
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(ArchivePalette.archivePaper)
    }

    /// 形态徽章文案（与时间流卡片保持一致 —— 统一走 EntryType.badgeLabel）
    static func entryTypeBadge(_ raw: String) -> String {
        EntryType(rawValue: raw)?.badgeLabel ?? "日常随笔"
    }
}
