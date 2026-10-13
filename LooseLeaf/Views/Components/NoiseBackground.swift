import SwiftUI
import AppKit

// 注：语义色盘 (ArchivePalette)、字体令牌 (ArchiveTypography) 与资源 Bundle 定位器
// 已抽出至 Models/ArchiveTokens.swift。

/// macOS 原生毛玻璃半透明背景桥接 (NSVisualEffectView)
public struct WindowVibrancyView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .underWindowBackground,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// 微噪点纸面材质背景组件 (docs/macos.md §6.1 & §7)
/// 融合 macOS 系统 Vibrancy、米白暖调棉纸/暗房碳黑底色与 0.03 柔和纸张颗粒纹理
public struct NoiseBackground: View {
    public var useSubtleSurface: Bool
    public var enableVibrancy: Bool
    public var grainOpacity: Double

    public init(
        useSubtleSurface: Bool = false,
        enableVibrancy: Bool = true,
        grainOpacity: Double = 0.03
    ) {
        self.useSubtleSurface = useSubtleSurface
        self.enableVibrancy = enableVibrancy
        self.grainOpacity = grainOpacity
    }

    public var body: some View {
        ZStack {
            if enableVibrancy {
                WindowVibrancyView()
                    .opacity(0.35)
            }

            (useSubtleSurface ? ArchivePalette.archiveSubtle : ArchivePalette.archivePaper)
                .opacity(enableVibrancy ? 0.94 : 1.0)

            PaperGrainCanvas(opacity: grainOpacity)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// 零外部依赖的纸本微噪点纹理层
/// 噪点图案由确定性 hash 生成——同尺寸/透明度下渲染一次并缓存为 CGImage，
/// 视图刷新时仅贴图（此前用 Canvas 逐点绘制，每次状态变化都会全屏重画数千个点，是掉帧感的主要来源）。
private struct PaperGrainCanvas: View {
    let opacity: Double

    var body: some View {
        GeometryReader { geo in
            if let image = PaperGrainCache.image(for: geo.size, opacity: opacity) {
                Image(decorative: image, scale: 2, orientation: .up)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

/// 纸纹位图缓存（最近 3 个尺寸条目，窗口/面板尺寸切换不互相踢出）
private enum PaperGrainCache {
    struct Entry {
        let size: CGSize
        let opacity: Double
        let image: CGImage
    }

    static var entries: [Entry] = []
    private static let lock = NSLock()

    static func image(for size: CGSize, opacity: Double) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = entries.first(where: { $0.size == size && $0.opacity == opacity }) {
            return hit.image
        }

        // 固定 2x 渲染：retina 清晰，非 retina 由系统自然下采样
        let renderScale: CGFloat = 2
        let pixelW = max(1, Int(size.width * renderScale))
        let pixelH = max(1, Int(size.height * renderScale))
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: renderScale, y: renderScale)
        let step: CGFloat = 14
        let cols = Int(size.width / step) + 1
        let rows = Int(size.height / step) + 1
        let ink = CGColor(gray: 0.09, alpha: opacity)

        ctx.setFillColor(ink)
        for row in 0..<rows {
            for col in 0..<cols {
                let hash = UInt64((row &* 73856093) ^ (col &* 19349663))
                if hash % 3 == 0 {
                    let offsetX = CGFloat((hash >> 3) % 11)
                    let offsetY = CGFloat((hash >> 7) % 11)
                    let dotSize: CGFloat = (hash % 2 == 0) ? 1.1 : 0.75
                    let rect = CGRect(
                        x: CGFloat(col) * step + offsetX,
                        y: CGFloat(row) * step + offsetY,
                        width: dotSize,
                        height: dotSize
                    )
                    ctx.fillEllipse(in: rect)
                }
            }
        }

        guard let image = ctx.makeImage() else { return nil }
        entries.append(Entry(size: size, opacity: opacity, image: image))
        if entries.count > 3 { entries.removeFirst(entries.count - 3) }
        return image
    }
}
