import XCTest
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 轻量快照测试工具 (Lightweight Snapshot Testing)
///
/// **不引入任何第三方依赖**：用 `NSHostingView` 把 SwiftUI 视图离屏渲染成位图，
/// 与 `__Snapshots__/` 目录下的基准图逐像素比较。
///
/// 首次运行某个快照时会**自动写入基准图**（并提示），之后的运行即做严格比对。
/// 视觉回归（字号、行距、颜色、圆角被误改）因此能在 CI 中被拦住。
@MainActor
enum SnapshotTester {

    /// 基准图目录（相对于测试文件所在目录）
    static var referenceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LooseLeafTests
            .deletingLastPathComponent()   // mac
            .appendingPathComponent("LooseLeafTests/__Snapshots__", isDirectory: true)
    }

    /// 渲染视图并与基准图比对
    /// - Parameters:
    ///   - view: 待测视图
    ///   - name: 快照名（对应 `__Snapshots__/<name>.png`）
    ///   - size: 渲染尺寸
    ///   - tolerance: 允许的像素差异比例（0~1）
    static func assertSnapshot(
        of view: some View,
        named name: String,
        size: CGSize = CGSize(width: 420, height: 320),
        tolerance: Double = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let image = render(view, size: size)
        let referenceURL = referenceDirectory.appendingPathComponent("\(name).png")

        guard let current = pngData(from: image) else {
            XCTFail("无法把快照「\(name)」编码为 PNG", file: file, line: line)
            return
        }

        if !FileManager.default.fileExists(atPath: referenceURL.path) {
            try? FileManager.default.createDirectory(at: referenceDirectory, withIntermediateDirectories: true)
            try? current.write(to: referenceURL, options: .atomic)
            print("📸 已写入新的快照基准：\(referenceURL.lastPathComponent)")
            return
        }

        guard let reference = NSImage(contentsOf: referenceURL),
              let referenceData = pngData(from: reference),
              let referenceBitmap = NSBitmapImageRep(data: referenceData),
              let currentBitmap = NSBitmapImageRep(data: current) else {
            XCTFail("无法读取快照基准「\(name)」", file: file, line: line)
            return
        }

        let difference = pixelDifferenceRatio(
            lhs: currentBitmap,
            rhs: referenceBitmap
        )
        XCTAssertLessThanOrEqual(
            difference,
            tolerance,
            "快照「\(name)」与基准图差异过大（\(String(format: "%.4f", difference)) > \(tolerance)），请检查视觉是否被意外改动",
            file: file,
            line: line
        )
    }

    // MARK: - 渲染

    private static func render(_ view: some View, size: CGSize) -> NSImage {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: .aqua)

        // 触发一次布局与绘制
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return NSImage(size: size)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return data
    }

    /// 逐像素比较，返回差异像素占比
    private static func pixelDifferenceRatio(lhs: NSBitmapImageRep, rhs: NSBitmapImageRep) -> Double {
        let width = min(lhs.pixelsWide, rhs.pixelsWide)
        let height = min(lhs.pixelsHigh, rhs.pixelsHigh)
        guard width > 0, height > 0 else { return 1 }

        var differing = 0
        let total = width * height
        for y in 0..<height {
            for x in 0..<width {
                let a = lhs.colorAt(x: x, y: y)
                let b = rhs.colorAt(x: x, y: y)
                let dr = abs((a?.redComponent ?? 0) - (b?.redComponent ?? 0))
                let dg = abs((a?.greenComponent ?? 0) - (b?.greenComponent ?? 0))
                let db = abs((a?.blueComponent ?? 0) - (b?.blueComponent ?? 0))
                if dr > 0.02 || dg > 0.02 || db > 0.02 {
                    differing += 1
                }
            }
        }
        return Double(differing) / Double(total)
    }
}
