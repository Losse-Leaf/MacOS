import XCTest
import SwiftUI
import AppKit
@testable import LooseLeaf

/// 客户端 UI 渲染开销基准 (UI Rendering Cost Benchmark)
///
/// 背景：用户反馈「点修改 / 创建内容很卡」。走查显示**后端 API 全是毫秒级**，
/// 因此瓶颈必然在客户端。本测试用 `NSHostingView` 真实渲染每个视图，
/// 量化「打开一个界面要花多久」，把主观的「卡」变成可比较的数字。
///
/// 注意：这是**基准**而非断言（不同机器差异大），只打印数据 + 对明显回归设宽松上限。
@MainActor
final class UIRenderingBenchmarkTests: XCTestCase {

    private var results: [(String, TimeInterval)] = []

    override func tearDown() async throws {
        print("──────── UI 渲染开销 ────────")
        for (name, elapsed) in results {
            let flag = elapsed > 0.25 ? "  ⚠️ 慢" : ""
            print(String(format: "  %-40@ %6.1f ms%@", name as NSString, elapsed * 1000, flag as NSString))
        }
        results = []
    }

    /// 渲染一个视图并测量耗时（强制布局 + 位图缓存绘制，覆盖整个 body 求值与排版）。
    ///
    /// 关键：**渲染两次取第二次**。SwiftUI 运行时第一次挂载任意视图都有约 70ms 的
    /// 固定初始化成本（实测基线：第一次 74.9ms、第二次 0.9ms），
    /// 把它算进每个视图会让所有数字失真、无法定位真正的热点。
    private func measure(_ name: String, size: CGSize = CGSize(width: 1080, height: 800), _ view: () -> some View) {
        var best: TimeInterval = .greatestFiniteMagnitude
        for _ in 0..<3 {
            let start = Date()
            let hosting = NSHostingView(rootView: view())
            hosting.frame = CGRect(origin: .zero, size: size)
            hosting.appearance = NSAppearance(named: .aqua)
            hosting.layoutSubtreeIfNeeded()
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
            }
            // 取三轮最小值：最小值最不受机器负载干扰，最能反映真实开销
            best = min(best, Date().timeIntervalSince(start))
        }
        let elapsed = best
        results.append((name, elapsed))
        print(String(format: "  %-40@ %6.1f ms", name as NSString, elapsed * 1000))
    }

    // MARK: - 基线：SwiftUI 首次挂载的固有开销

    /// 量出「挂载一个几乎为空的视图」要花多久 —— 这是所有视图都无法逃脱的固定成本。
    /// 后面各视图的耗时减去它，才是视图**自身**的真实开销。
    func test00_BaselineHostingCost() {
        measure("【基线】空视图挂载") {
            Color.clear.frame(width: 400, height: 200)
        }
        measure("【基线】空视图挂载（第二次）") {
            Color.clear.frame(width: 400, height: 200)
        }
    }

    // MARK: - 逐项拆解创作弹窗的开销

    func test07_ComposerBreakdown() {
        let entry = LifeEntry(
            id: 1,
            type: "life",
            title: "拆解基准",
            content: "正文",
            occurredAt: "2026-10-20T10:00:00+08:00"
        )
        measure("拆解·单个 TextField") {
            TextField("标题", text: .constant("x"))
                .textFieldStyle(.plain)
                .frame(width: 400, height: 40)
        }
        measure("拆解·PaperPillButton 组") {
            HStack {
                ForEach(0..<6) { i in
                    PaperPillButton(title: "胶囊\(i)", isSelected: i == 0) {}
                }
            }
            .frame(width: 500, height: 40)
        }
        measure("拆解·paperElevation 卡片") {
            VStack { Text("内容") }
                .padding(14)
                .background(ArchivePalette.archivePaper)
                .paperElevation(1)
                .frame(width: 500, height: 120)
        }
        measure("拆解·时间流卡片（再测一次）") {
            TimelineEntryCardView(
                entry: entry,
                transaction: nil,
                isKeyboardFocused: false,
                actions: TimelineEntryActions()
            )
            .frame(width: 900, height: 160)
        }
    }

    // MARK: - 验证：SwiftUI .shadow 的代价

    func test08_ShadowCostComparison() {
        let content = VStack(alignment: .leading, spacing: 8) {
            Text("卡片标题")
                .font(ArchiveTypography.editorialSerif(size: 15, weight: .medium))
            Text("这是卡片正文，用来测量阴影带来的渲染开销。")
                .font(ArchiveTypography.bodySans(size: 12))
        }
        .padding(14)
        .frame(width: 500, alignment: .leading)
        .background(ArchivePalette.archivePaper)
        .clipShape(RoundedRectangle(cornerRadius: 6))

        measure("对照·无阴影") { content }
        measure("对照·SwiftUI .shadow(radius:6,y:2)") {
            content.shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 2)
        }
        measure("对照·SwiftUI .shadow(radius:2,y:1)") {
            content.shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        }
        measure("对照·AppKit NSShadow") {
            content
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ArchivePalette.archivePaper)
                        .shadow(color: Color.black.opacity(0.10), radius: 2, x: 0, y: 1)
                )
        }
        measure("对照·纯描边（无阴影）") {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
        }
        measure("对照·阴影只作用于背景矩形") {
            content
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ArchivePalette.archivePaper)
                        .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 2)
                )
        }
        measure("对照·阴影只作用于背景矩形 + 描边") {
            content
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ArchivePalette.archivePaper)
                        .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ArchivePalette.borderSubtle, lineWidth: 0.5)
                )
        }
    }

    // MARK: - 创作弹窗内部逐项拆解

    func test09_ComposerInternalBreakdown() {
        let draft = EntryDraft()

        measure("弹窗拆解·形态切换条（5 个胶囊）") {
            HStack(spacing: 6) {
                ForEach(["life", "travel", "project", "wish", "transaction"], id: \.self) { kind in
                    PaperPillButton(title: kind, isSelected: kind == "life") {}
                }
            }
            .frame(width: 700, height: 40)
        }
        measure("弹窗拆解·标题 + 正文输入") {
            VStack(spacing: 12) {
                TextField("标题", text: .constant("x"))
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                TextField("正文", text: .constant("y"), axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(ArchivePalette.archiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(width: 700, height: 160)
        }
        measure("弹窗拆解·附件区 EntryMediaAttachmentsSection") {
            EntryMediaAttachmentsSection(media: EntryMediaState())
                .frame(width: 700, height: 120)
        }
        // 对照：同样的内容，但**不注册**宽泛的 .onDrop
        measure("弹窗拆解·对照（无 .onDrop 的静态附件区）") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("胶片与图档装裱 (0)")
                        .font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption, weight: .medium))
                    Spacer()
                    Button {} label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard").font(.system(size: 10.5))
                            Text("粘贴相纸").font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                    Button {} label: {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 10.5))
                            Text("添加相纸照片").font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
                        }
                    }
                    .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                }
            }
            .frame(width: 700, height: 120)
        }
        // 对照：注册 .onDrop 但只声明窄的 UTI
        measure("弹窗拆解·对照（.onDrop 只声明 fileURL）") {
            VStack {
                Text("x")
            }
            .frame(width: 700, height: 120)
            .onDrop(of: [.fileURL], isTargeted: .constant(false)) { _ in false }
        }
        measure("弹窗拆解·日期 + 城市 + 精选") {
            HStack(spacing: 12) {
                PaperDatePicker(selection: .constant(Date()), enableTime: true, label: "发生时刻")
                PaperCityPicker(selectedCode: .constant("330100"), selectedName: .constant("杭州市"), placeholder: "点选城市…")
                Toggle("精选", isOn: .constant(false))
                    .toggleStyle(PaperCheckboxToggleStyle())
            }
            .frame(width: 700, height: 60)
        }
        measure("弹窗拆解·形态分支本身（life）") {
            EntryModalLifeForm(draft: draft, media: EntryMediaState())
                .frame(width: 700, height: 300)
        }
    }

    // MARK: - 按钮样式对照

    func test10_ButtonStyleComparison() {
        let label = { HStack(spacing: 4) {
            Image(systemName: "photo.badge.plus").font(.system(size: 10.5))
            Text("添加相纸照片").font(ArchiveTypography.bodySans(size: ArchiveTypography.Scale.caption))
        } }

        measure("按钮·.plain（无自定义样式）") {
            Button {} label: { label() }
                .buttonStyle(.plain)
                .frame(width: 160, height: 40)
        }
        measure("按钮·PaperPrimaryButtonStyle") {
            Button {} label: { label() }
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
                .frame(width: 160, height: 40)
        }
        measure("按钮·PaperPillButton") {
            PaperPillButton(title: "添加相纸照片", isSelected: false) {}
                .frame(width: 160, height: 40)
        }
    }

    // MARK: - 列表内卡片（每张都会重复渲染）

    func test11_ListCardRenderingCost() {
        measure("心愿卡 WishCardView") {
            WishCardView(wish: Wish(id: 1, title: "走查心愿", kind: "item", note: "备注"), onResolve: {}, onEdit: {}, onDelete: {})
                .frame(width: 300, height: 195)
        }
        measure("造物卡 ProjectCardView") {
            ProjectCardView(proj: Project(id: 1, title: "走查造物", description: "描述"), onEdit: {}, onDelete: {})
                .frame(width: 300, height: 195)
        }
        measure("相纸框 FilmFrameView") {
            FilmFrameView(imageURL: nil, localImage: nil, caption: "走查相纸", metaText: "2026-03-01")
                .frame(width: 220, height: 160)
        }
    }

    // MARK: - 各主界面

    func test01_MainSectionRenderingCost() {
        let appState = AppState.shared
        measure("侧栏 WorkbenchSidebar") {
            WorkbenchSidebar(appState: appState, isSystemGroupCollapsed: .constant(false), onSelect: { _ in })
                .frame(width: 225, height: 800)
        }
    }

    func test02_TimelineCardRenderingCost() {
        let entry = LifeEntry(
            id: 1,
            type: "life",
            title: "渲染开销基准",
            content: "这是一段用于测量渲染开销的正文内容，长度适中。",
            occurredAt: "2026-10-20T10:00:00+08:00"
        )
        measure("时间流单卡 TimelineEntryCardView") {
            TimelineEntryCardView(
                entry: entry,
                transaction: nil,
                isKeyboardFocused: false,
                actions: TimelineEntryActions()
            )
            .frame(width: 900, height: 160)
        }
    }

    func test03_NewEntryModalRenderingCost() {
        let appState = AppState.shared
        measure("创作弹窗 NewEntryModal（日常）") {
            NewEntryModal(
                appState: appState,
                initialKind: "life",
                initialProjectId: nil,
                initialCityCode: nil,
                initialCityName: nil
            ) { }
            .frame(width: 720, height: 620)
        }
    }

    func test04_ComposerSubFormRenderingCost() {
        // 五个形态分支各自的渲染开销
        for kind in ["life", "travel", "project", "wish", "transaction"] {
            let appState = AppState.shared
            measure("创作弹窗形态分支 · \(kind)") {
                NewEntryModal(
                    appState: appState,
                    initialKind: kind,
                    initialProjectId: nil,
                    initialCityCode: nil,
                    initialCityName: nil
                ) { }
                .frame(width: 720, height: 620)
            }
        }
    }

    func test05_HeavyPickerRenderingCost() {
        // 城市选择器与日期选择器是最重的两个控件
        measure("城市选择器 PaperCityPicker") {
            PaperCityPicker(selectedCode: .constant("330100"), selectedName: .constant("杭州市"), placeholder: "点选城市…")
                .frame(width: 400, height: 60)
        }
        measure("日期选择器 PaperDatePicker") {
            PaperDatePicker(selection: .constant(Date()), enableTime: true, label: "发生时刻")
                .frame(width: 320, height: 60)
        }
    }

    func test06_SettingsPageRenderingCost() {
        let appState = AppState.shared
        measure("偏好设置页") {
            PreferencesSettingsView(appState: appState)
                .frame(width: 720, height: 800)
        }
    }
}
