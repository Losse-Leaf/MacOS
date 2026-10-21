import SwiftUI
import AppKit

    /// 时间流条目卡片。
    ///
    /// **纯值输入**：卡片不再持有 `@Bindable appState`。
    /// 原实现让每一行都成为一个 AppState 观察者 —— N 行 = N 个观察者，
    /// 任一状态变更都会唤醒全部卡片；且卡片内部还要现查账目（O(N) 遍历）。
    /// 现在账目由父层按 id 查好后作为值传入，交互一律通过闭包回传。
    /// 时间流卡片的行为集合（把 8 个闭包打包成一个值类型，
    /// 既让卡片初始化表达式保持简短，也降低 SwiftUI 类型检查器的负担）
    /// 时间流卡片的行为集合。
    ///
    /// **关键：必须是引用类型且全表共享同一个实例。**
    ///
    /// 早先这里是值类型（struct），由父层在 `ForEach` 里**逐卡**构造：
    /// ```swift
    /// ForEach(rows) { row in
    ///     TimelineEntryCardView(..., actions: timelineActions(for: row.entry))
    /// }
    /// ```
    /// 每次父视图重算，`actions` 都是一份**全新的闭包集合** → 传给卡片的视图值
    /// 随之改变 → SwiftUI 认为「这张卡变了」→ **无法跳过任何一张卡的重绘**。
    /// 于是连点一下弹窗这种与时间流无关的操作，也会让整列 60 张卡全部重算：
    /// 实测点「记一笔」要 **192ms**，而弹窗本身单独渲染只要 12ms。
    ///
    /// 改成引用类型 + 全体共享同一实例后，视图值保持稳定，
    /// SwiftUI 才能真正跳过那些内容没变的卡片。
    /// 为了让「同一份行为」能作用于不同的条目，闭包改为**接收条目参数**。
    /// 卡片 body 求值计数器（诊断用）
    ///
    /// 关键指标：**一次操作让多少张卡片重新求值 body**。
    /// SwiftUI 只有在视图值真的变了时才会重绘；一旦某个改动让整列 60 张卡
    /// 全部重算，用户看到的就是「点哪儿都卡一下」。
    /// 生产构建里不计数（DEBUG 之外编译为空操作）。
    enum TimelineRenderCounter {
        #if DEBUG
        nonisolated(unsafe) static var cardBodyEvaluations: Int = 0
        static func reset() { cardBodyEvaluations = 0 }
        static var value: Int { cardBodyEvaluations }
        #else
        static func reset() {}
        static var value: Int { 0 }
        #endif
    }

    /// 计数用的视图修饰符（Modifier 的 body 是普通函数，可以放计数语句）
    private struct CountCardRender: ViewModifier {
        func body(content: Content) -> some View {
            #if DEBUG
            TimelineRenderCounter.cardBodyEvaluations += 1
            #endif
            return content
        }
    }

    @MainActor
    final class TimelineEntryActions {
        /// 绑定到 AppState 单例。
        ///
        /// 闭包只捕获 `AppState.shared`（单例），因此这个实例一旦创建，
        /// 其行为集合在整个 App 生命周期内**恒定不变** —— 这正是 SwiftUI
        /// 跳过「内容没变的卡片」所需要的前提。
        init(appState: AppState? = nil) {
            // 默认参数在调用方上下文求值，而 `AppState.shared` 是 MainActor 隔离的，
            // 所以默认值不能直接写 `.shared`（Swift 6 下是错误），改为在 init 内部解析。
            let state = appState ?? AppState.shared
            onEditEntry = { entry in state.editingEntry = entry }
            onEditTransaction = { tx in state.editingTransaction = tx }
            onOpenDetail = { entry in
                // 给主线程卡顿归因：出问题时能知道当时用户点的是哪一步
                MainThreadWatchdog.shared.noteAction("点击卡片（打开详情）")
                state.highlightedEntry = entry
            }
            onOpenLightbox = { attachment in state.lightboxAttachment = attachment }
            onToast = { message in state.showTemporaryBanner(message) }
            onRetrySync = { id in state.retryFailedEntry(id: id) }
            onReuploadEntry = { entry in state.reuploadEntry(id: entry.id) }
            onDeleteEntry = { entry in
                state.askConfirm(
                    title: ArchiveSharedCopy.entryDeleteTitle,
                    message: ArchiveSharedCopy.entryDeleteMessage,
                    confirmText: ArchiveSharedCopy.entryDeleteConfirmText,
                    danger: true
                ) {
                    state.deleteEntryAction(entry)
                }
            }
            onDeleteTransaction = { tx in
                state.askConfirm(
                    title: ArchiveSharedCopy.transactionDeleteTitle,
                    message: ArchiveSharedCopy.transactionDeleteMessage,
                    confirmText: ArchiveSharedCopy.transactionDeleteConfirmText,
                    danger: true
                ) {
                    state.deleteTransactionAction(tx)
                }
            }
        }

        /// 编辑散页
        var onEditEntry: (LifeEntry) -> Void = { _ in }
        /// 删除散页
        var onDeleteEntry: (LifeEntry) -> Void = { _ in }
        /// 编辑账目
        var onEditTransaction: (Transaction) -> Void = { _ in }
        /// 删除账目
        var onDeleteTransaction: (Transaction) -> Void = { _ in }
        /// 切换精选
        /// 打开详情
        var onOpenDetail: (LifeEntry) -> Void = { _ in }
        /// 打开灯箱
        var onOpenLightbox: (Attachment) -> Void = { _ in }
        /// 顶部提示条
        var onToast: (String) -> Void = { _ in }
        /// 重试同步失败的记录
        var onRetrySync: (Int) -> Void = { _ in }
        /// 重新上传一条「待同步」的散页
        var onReuploadEntry: (LifeEntry) -> Void = { _ in }
    }

    struct TimelineEntryCardView: View {
        let entry: LifeEntry
        /// 紧凑时间戳（朋友圈式；空串表示与上一条同一分钟，折叠不显示）
        var timeLabel: String = ""
        /// 关联账目（由父层按 id 查好后传入，避免卡片内全量遍历）
        let transaction: Transaction?
        /// 是否为键盘流当前聚焦项
        var isKeyboardFocused: Bool = false
        var actions: TimelineEntryActions = TimelineEntryActions()

        @State private var isHovering: Bool = false

        private var parsed: FormatUtils.ParsedBeijingDate {
            entry.parsedDate
        }

        private var typeAccentColor: Color {
            switch entry.type {
            case "travel": return ArchivePalette.accentWarm
            case "project": return Color("SpectrumStudy", bundle: ArchiveResourceBundle.bundle)
            case "wish": return Color("SpectrumLeisure", bundle: ArchiveResourceBundle.bundle)
            case "transaction": return Color("SpectrumDining", bundle: ArchiveResourceBundle.bundle)
            default: return ArchivePalette.accentMoss
            }
        }

        private var entryTypeBadgeName: String {
            switch entry.type {
            case "travel": return "山川游历"
            case "project": return "造物演进"
            case "wish": return "心愿印记"
            case "transaction": return "柴米油盐"
            case "gear": return "器物印记"
            default: return "日常随笔"
            }
        }

        var body: some View {
            HStack(alignment: .top, spacing: 0) {
                // 左侧时光节点：只陪元信息行，不再贯穿整张卡
                //
                // 早先是一根 3pt 宽的实心色条贴着卡片左边缘内侧 ——
                // 看着像残留的装饰。现在收成「一枚节点 + 一小截引线」，
                // 长度只够到元信息行下方，像时间轴上的一个刻度，
                // 而不是一根从头贯到尾的栏杆。
                VStack(spacing: 0) {
                    Circle()
                        .fill(typeAccentColor)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                    Rectangle()
                        .fill(typeAccentColor.opacity(0.22))
                        .frame(width: 1, height: 12)
                }
                .padding(.trailing, 12)

                VStack(alignment: .leading, spacing: 9) {
                    // 顶栏：形态印章 + 时刻 + 地点 + 悬停优雅动作
                    //
                    // 关键：**日期不再出现在卡片里** —— 它已由上方的「按天分组标题」承担。
                    // 每张卡都重复一遍日期，既是噪音，也让卡片失去了「一页」的密度。
                    HStack(spacing: 7) {
                        Text(entryTypeBadgeName)
                            .font(ArchiveTypography.monoScale(size: 10, weight: .medium))
                            .foregroundStyle(typeAccentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(typeAccentColor.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.xs))


                        if let loc = entry.location ?? entry.cityName, !loc.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "location")
                                    .font(.system(size: 9.5))
                                Text(loc)
                                    .font(ArchiveTypography.bodySans(size: 11))
                            }
                            .foregroundStyle(ArchivePalette.inkMuted)
                        }

                        // 同步状态：待同步（网络未通）/ 同步失败（可重试）
                        //
                        // 关键：两种状态都给出「重传」入口。
                        // 「待同步」的条目同样可能卡住不动（发件箱死信被丢弃、
                        // 进程在同步途中被杀）—— 没有重传入口的话，用户只能干等。
                        let syncState = entry.syncStatus ?? "synced"
                        if syncState == "pending_create" {
                            Text("待同步")
                                .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                                .foregroundStyle(ArchivePalette.accentWarm)
                                .accessibilityLabel("待同步到中枢")

                            Button {
                                actions.onReuploadEntry(entry)
                            } label: {
                                Text("重传")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .help("重新上传这条记录到中枢")
                            .accessibilityLabel("重新上传到中枢")
                        } else if syncState == "failed" {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                                    .font(.system(size: 9.5))
                                Text("同步失败")
                                    .font(ArchiveTypography.monoScale(size: ArchiveTypography.Scale.micro))
                            }
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .help("该条记录未能同步到中枢，点击重试")
                            .accessibilityLabel("同步失败")

                            Button {
                                actions.onRetrySync(entry.id)
                            } label: {
                                Text("重试")
                                    .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.micro, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(ArchivePalette.accentWarm)
                            .help("重新同步到中枢")
                            .accessibilityLabel("重试同步")
                        }

                        // 时间戳紧跟类型印章 —— 元信息聚成一团，
                        // 而不是把时间孤零零甩到最右（那样眼睛要横跨整行去找它）
                        if !timeLabel.isEmpty {
                            Text(timeLabel)
                                .font(ArchiveTypography.monoScale(size: 10.5))
                                .foregroundStyle(ArchivePalette.inkMuted.opacity(0.85))
                                .monospacedDigit()
                        }

                        Spacer()

                        // 右侧操作：仅在鼠标悬停时优雅淡现，默认保持日记纯粹无噪点
                        HStack(spacing: 6) {
                            if isHovering {
                                if entry.type == "transaction" {
                                    if let tx = transaction {
                                        Button {
                                            actions.onEditTransaction(tx)
                                        } label: {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 11))
                                                .foregroundStyle(ArchivePalette.inkSecondary)
                                                .frame(width: 24, height: 24)
                                                .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("编辑账目")
                                        .accessibilityLabel("编辑账目")

                                        Button {
                                            actions.onDeleteTransaction(tx)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundStyle(ArchivePalette.accentWarm)
                                                .frame(width: 24, height: 24)
                                                .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("删除账目")
                                        .accessibilityLabel("删除账目")
                                    }
                                } else {
                                    Button {
                                        actions.onEditEntry(entry)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 11))
                                            .foregroundStyle(ArchivePalette.inkSecondary)
                                            .frame(width: 24, height: 24)
                                            .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("编辑手稿")
                                        .accessibilityLabel("编辑手稿")

                                    Button {
                                        actions.onDeleteEntry(entry)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundStyle(ArchivePalette.accentWarm)
                                            .frame(width: 24, height: 24)
                                            .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("删除手稿")
                                        .accessibilityLabel("删除手稿")
                                }
                            }

                            // 关键：这一枚此前是**常驻**的，而同行其它动作都只在悬停时出现 ——
                            // 于是每张卡右上角都挂着一个孤零零的小方框，看着像没画完。
                            // 现在统一：悬停时才淡入。
                            if isHovering {
                                Button {
                                    actions.onOpenDetail(entry)
                                } label: {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(ArchivePalette.inkMuted)
                                        .frame(width: 24, height: 24)
                                        .background(ArchivePalette.archiveSubtle.opacity(0.8))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("查看手稿完整详情")
                                .accessibilityLabel("查看手稿完整详情")
                            }
                        }
                        // 关键：这里原本绑着一个 `value: isHovering` 的动画。
                        // 滚动时悬停被疯狂触发，每个悬停都会开启一次 Core Animation
                        // 事务，持续占用主线程 —— 这是滚动卡顿的帮凶。
                        // 悬停反馈改为即时生效（无动画），观感差异极小，开销归零。
                        .animation(nil, value: isHovering)
                    }

                    // 朋友圈式发布：标题常与正文第一行相同（标题就是从那儿派生的），
                    // 这时再单独显示一遍就是重复。相同则只显示正文。
                    let derived = FormatUtils.derivedTitle(from: entry.content)
                    if !entry.title.isEmpty && entry.title != derived {
                        Text(entry.title)
                            .font(ArchiveTypography.editorialSerif(size: 17, weight: .semibold))
                            .foregroundStyle(ArchivePalette.inkPrimary)
                            .padding(.bottom, 1)
                    }

                    Text(entry.content)
                        .font(ArchiveTypography.bodySans(size: 13.5))
                        .foregroundStyle(ArchivePalette.inkPrimary.opacity(0.9))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .textSelection(.enabled)

                    // 附件胶片相框画廊 (.film-frame)
                    if !entry.attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(entry.attachments) { att in
                                    // 列表用**缩略图**（几十 KB），原图留给灯箱。
                                    // 关键：这里以前直接拉原图（1.5MB/张），
                                    // 滚动时每张新卡片都要下 1.5MB —— 网络与解码把主线程打满。
                                    let displayURL = att.thumbnailUrl ?? att.url
                                    if let url = APIClient.shared.resolveMediaURL(displayURL) {
                                        FilmFrameView(
                                            imageURL: url,
                                            caption: entry.title.isEmpty ? att.originalFilename : entry.title,
                                            metaText: parsed.dotDate,
                                            maxHeight: 220
                                        ) {
                                            actions.onOpenLightbox(att)
                                        }
                                        .frame(width: 260)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(ArchivePalette.archivePaper)
            .clipShape(RoundedRectangle(cornerRadius: ArchiveRadius.md))
            .paperElevation(isHovering ? 2 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: ArchiveRadius.md)
                    .stroke(
                        isKeyboardFocused ? ArchivePalette.accentWarm : Color.clear,
                        lineWidth: 1.0
                    )
            )
            .onHover { isHovering = $0 }
            .contentShape(Rectangle())
            .modifier(CountCardRender())
            .onTapGesture(count: 2) {
                actions.onOpenDetail(entry)
            }
            .contextMenu {
                if entry.type == "transaction" {
                    if let tx = transaction {
                        Button {
                            actions.onEditTransaction(tx)
                        } label: {
                            Label("编辑账目", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            actions.onDeleteTransaction(tx)
                        } label: {
                            Label("删除账目", systemImage: "trash")
                        }
                        Divider()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(FormatUtils.formattedYuan(cents: tx.amount), forType: .string)
                            actions.onToast("已拷贝金额至剪贴板")
                        } label: {
                            Label("拷贝金额", systemImage: "doc.on.doc")
                        }
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(tx.title.isEmpty ? tx.category : tx.title, forType: .string)
                            actions.onToast("已拷贝账目摘要至剪贴板")
                        } label: {
                            Label("拷贝账目摘要", systemImage: "text.quote")
                        }
                    }
                } else {
                    Button {
                        actions.onOpenDetail(entry)
                    } label: {
                        Label("查看手稿详情", systemImage: "book.pages")
                    }
                    Button {
                        actions.onEditEntry(entry)
                    } label: {
                        Label("编辑手稿", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        actions.onDeleteEntry(entry)
                    } label: {
                        Label("删除手稿", systemImage: "trash")
                    }
                    Divider()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.content, forType: .string)
                        actions.onToast("已拷贝手稿正文至剪贴板")
                    } label: {
                        Label("拷贝手稿正文", systemImage: "doc.on.doc")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(parsed.dotDateTime, forType: .string)
                        actions.onToast("已拷贝时间戳至剪贴板")
                    } label: {
                        Label("拷贝时间戳", systemImage: "clock")
                    }
                }
            }
            // ��前这里还挂着 `.paperHover()`，与卡片自身的 `.onHover` 构成
            // **两套**悬停状态机：每次指针扫过都要触发两次状态变更与两次重绘。
            // 卡片本来就有自己的悬停底色与描边反馈，`.paperHover()` 是多余的。
            // 去掉它。
        }
    }
