import XCTest
import SwiftUI
import AppKit
@testable import LooseLeaf

/// 离屏渲染快照 (Visual Snapshot Harness)
///
/// 目的：阴影层级被改写后，必须用眼睛确认界面**依然成立**，
/// 而不是只看性能数字。本测试把关键视图离屏渲染成 PNG，便于人工比对。
///
/// 产物写入 `/tmp/looseleaf-snapshot/`。
@MainActor
final class VisualSnapshotTests: XCTestCase {

    private let outputDirectory = URL(fileURLWithPath: "/tmp/looseleaf-snapshot")

    override func setUp() async throws {
        try await super.setUp()
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    /// 渲染视图并导出 PNG
    private func snapshot(_ name: String, size: CGSize, _ view: () -> some View) {
        let hosting = NSHostingView(rootView: view())
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }

        let url = outputDirectory.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("📸 \(url.path)")
    }

    /// 时间流卡片（含相纸框）：验证描边层级在无阴影下依然清晰
    func test01_TimelineCardAppearance() {
        let image = NSImage(size: NSSize(width: 320, height: 200))
        image.lockFocus()
        NSColor(calibratedRed: 0.72, green: 0.66, blue: 0.55, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 320, height: 200).fill()
        NSColor(calibratedRed: 0.45, green: 0.52, blue: 0.44, alpha: 1).setFill()
        NSRect(x: 20, y: 20, width: 280, height: 160).fill()
        image.unlockFocus()

        let entry = LifeEntry(
            id: 1,
            type: "life",
            title: "搬进新居的第一天",
            content: "把书架靠到窗边，下午的光正好落在书脊上。顺手拍了一张，纸的味道还没散。",
            occurredAt: "2026-10-20T10:00:00+08:00"
        )

        snapshot("01-时间流卡片", size: CGSize(width: 860, height: 220)) {
            TimelineEntryCardView(
                entry: entry,
                transaction: nil,
                isKeyboardFocused: false,
                actions: TimelineEntryActions()
            )
            .frame(width: 860, height: 220)
            .background(ArchivePalette.archivePaper)
        }

        snapshot("02-相纸框", size: CGSize(width: 260, height: 200)) {
            FilmFrameView(imageURL: nil, localImage: image, caption: "窗边的光", metaText: "2026-10-20")
                .frame(width: 260, height: 200)
                .background(ArchivePalette.archivePaper)
        }
    }

    /// 心愿卡 / 造物卡 / 侧栏
    func test02_CardsAndSidebar() {
        snapshot("03-心愿卡", size: CGSize(width: 320, height: 210)) {
            WishCardView(
                wish: Wish(id: 1, title: "换一把手写钢笔", kind: "item", note: "想要一支能日常写的中性笔"),
                onResolve: {}, onEdit: {}, onDelete: {}
            )
            .frame(width: 320, height: 210)
            .background(ArchivePalette.archivePaper)
        }

        snapshot("04-造物卡", size: CGSize(width: 320, height: 210)) {
            ProjectCardView(
                proj: Project(id: 1, title: "写一个随手记工具", description: "把每天的碎片收进一个地方"),
                onEdit: {}, onDelete: {}
            )
            .frame(width: 320, height: 210)
            .background(ArchivePalette.archivePaper)
        }

        snapshot("05-侧栏", size: CGSize(width: 240, height: 620)) {
            WorkbenchSidebar(
                appState: AppState.shared,
                isSystemGroupCollapsed: .constant(false),
                onSelect: { _ in }
            )
            .frame(width: 240, height: 620)
            .background(ArchivePalette.archivePaper)
        }
    }

    /// 整个主窗口（侧栏 + 时间流）：这是用户一天要看几百眼的地方
    func test04_MainWindowAppearance() throws {
        let appState = AppState.shared
        let bodies = [
            "把书架靠到窗边，下午的光正好落在书脊上。顺手拍了一张，纸的味道还没散。",
            "今天走了很久的路，鞋底沾着傍晚的尘土。回来路上买了一支很便宜的钢笔。",
            "雨下了一整个下午。屋里很安静，听得见雨点打在玻璃上的声音。",
            "整理旧物，翻出来三年前的笔记本，字迹还很淡。",
            "和朋友在街角的小店坐了很久，什么正经事也没聊，就是坐着。",
            "清晨五点醒，窗外还是灰蓝色。给自己煮了咖啡，等天亮。",
            "看完了一本很厚的书，合上的时候有点舍不得。",
            "公园的银杏开始黄了，踩上去有很轻的脆响。"
        ]
        appState.entries = (0..<14).map { i in
            LifeEntry(
                id: i + 1,
                type: EntryType.life.rawValue,
                // 朋友圈式发布：没有独立标题，标题由正文首行派生
                title: "",
                content: bodies[i % bodies.count],
                occurredAt: "2026-09-\(String(format: "%02d", (i % 28) + 1))T10:00:00+08:00",
                cityCode: "330100",
                cityName: "杭州市"
            )
        }
        appState.transactions = (0..<6).map { i in
            var tx = Transaction(id: i + 1, amount: Int64(2500 + i * 137),
                                 type: "expense", category: "餐饮", title: "第 \(i + 1) 笔")
            tx.occurredAt = "2026-09-\(String(format: "%02d", (i % 28) + 1))T12:00:00+08:00"
            return tx
        }
        appState.wishes = (0..<5).map { i in
            Wish(id: i + 1, title: "第 \(i + 1) 个心愿", kind: "item", note: "想要一支能日常写的中性笔")
        }
        appState.projects = (0..<4).map { i in
            Project(id: i + 1, title: "第 \(i + 1) 个造物", description: "把每天的碎片收进一个地方")
        }

        snapshot("10-主窗口（侧栏+时间流）", size: CGSize(width: 1280, height: 820)) {
            StreamView(appState: appState)
                .frame(width: 1280, height: 820)
        }
        // 其它板块：确认时间流的改动没有波及它们
        for section in [WorkbenchSection.ledger, .wishes, .projects] {
            appState.activeSection = section
            snapshot("12-板块-\(section.rawValue)", size: CGSize(width: 1280, height: 820)) {
                StreamView(appState: appState)
                    .frame(width: 1280, height: 820)
            }
        }
        appState.activeSection = .stream

        snapshot("11-侧栏单独", size: CGSize(width: 225, height: 820)) {
            WorkbenchSidebar(appState: appState, isSystemGroupCollapsed: .constant(false), onSelect: { _ in })
                .frame(width: 225, height: 820)
                .background(ArchivePalette.archivePaper)
        }
    }

    /// 创作弹窗：确认各形态在无阴影下的层级与留白
    func test03_ComposerAppearance() {
        snapshot("06-创作弹窗-日常", size: CGSize(width: 760, height: 660)) {
            NewEntryModal(
                appState: AppState.shared,
                initialKind: "life",
                initialProjectId: nil,
                initialCityCode: nil,
                initialCityName: nil
            ) { }
            .frame(width: 760, height: 660)
            .background(ArchivePalette.archivePaper)
        }
    }
}
