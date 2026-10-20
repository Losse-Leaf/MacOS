import XCTest
import SwiftUI
@testable import LooseLeaf

/// 视觉回归快照测试 (Snapshot Tests)
///
/// 覆盖最容易被误改的视觉锚点：语义色板、纸张背景、胶囊按钮、主按钮样式、空状态。
/// 基准图位于 `LooseLeafTests/__Snapshots__/`，首次运行会自动生成。
@MainActor
final class ArchiveSnapshotTests: XCTestCase {

    /// 语义色板快照：颜色被误改会立刻被抓住
    func testSemanticPaletteSnapshot() {
        let swatches = HStack(spacing: 0) {
            ForEach(
                [
                    ("paper", ArchivePalette.archivePaper),
                    ("subtle", ArchivePalette.archiveSubtle),
                    ("ink", ArchivePalette.inkPrimary),
                    ("ink2", ArchivePalette.inkSecondary),
                    ("muted", ArchivePalette.inkMuted),
                    ("warm", ArchivePalette.accentWarm),
                    ("moss", ArchivePalette.accentMoss)
                ],
                id: \.0
            ) { _, color in
                color.frame(width: 60, height: 120)
            }
        }
        .frame(width: 420, height: 120)
        .background(ArchivePalette.archivePaper)

        SnapshotTester.assertSnapshot(of: swatches, named: "palette-semantic")
    }

    /// 纸纹背景快照
    func testPaperBackgroundSnapshot() {
        let background = ZStack {
            ArchivePalette.archivePaper
            NoiseBackground(useSubtleSurface: false, enableVibrancy: false)
        }
        .frame(width: 320, height: 200)

        SnapshotTester.assertSnapshot(of: background, named: "paper-background")
    }

    /// 胶囊按钮快照（选中 / 未选中 / 悬停三种态）
    func testPillButtonSnapshot() {
        let row = HStack(spacing: 8) {
            PaperPillButton(title: "全部印记", isSelected: true) {}
            PaperPillButton(title: "日常", isSelected: false) {}
            PaperPillButton(title: "游历", isSelected: false) {}
        }
        .padding(16)
        .frame(width: 320, height: 60)
        .background(ArchivePalette.archivePaper)

        SnapshotTester.assertSnapshot(of: row, named: "pill-buttons")
    }

    /// 主按钮样式快照（强调 / 普通）
    func testPrimaryButtonSnapshot() {
        let row = HStack(spacing: 8) {
            Button("记一笔") {}
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: true))
            Button("取消") {}
                .buttonStyle(PaperPrimaryButtonStyle(isProminent: false))
        }
        .padding(16)
        .frame(width: 320, height: 60)
        .background(ArchivePalette.archivePaper)

        SnapshotTester.assertSnapshot(of: row, named: "primary-buttons")
    }

    /// 空状态快照（含 CTA）
    func testEmptyStateSnapshot() {
        let state = ArchiveEmptyState(
            systemName: "book.closed",
            title: "散页手记尚待落墨",
            message: "记录真实可感的当下",
            primaryTitle: "记第一笔 (⌘N)",
            primaryAction: {}
        )
        .frame(width: 420, height: 240)
        .background(ArchivePalette.archivePaper)

        SnapshotTester.assertSnapshot(of: state, named: "empty-state")
    }
}
