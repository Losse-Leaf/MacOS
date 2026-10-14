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
/// 噪点图案由确定性 hash 在启动时生成一次 256x256 瓦片并缓存，
/// 渲染时由系统 Metal/CoreAnimation 硬件直接平铺（resizingMode: .tile），
/// 彻底消除此前每次窗口尺寸改变时全屏重画数千点导致的丢帧与内存激增。
private struct PaperGrainCanvas: View {
    let opacity: Double

    var body: some View {
        if let tile = PaperGrainTileCache.tileImage(opacity: opacity) {
            Image(decorative: tile, scale: 2)
                .resizable(resizingMode: .tile)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }
}

/// 纸纹 256x256 硬件瓦片缓存（同透明度只生成一次，内存占用 < 0.25MB）
private enum PaperGrainTileCache {
    private static var tileCache: [Double: CGImage] = [:]
    private static let lock = NSLock()

    static func tileImage(opacity: Double) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let key = (opacity * 1000).rounded() / 1000
        if let hit = tileCache[key] {
            return hit
        }

        let tileSize: CGFloat = 256
        let renderScale: CGFloat = 2
        let pixelSize = Int(tileSize * renderScale)
        guard let ctx = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: renderScale, y: renderScale)
        let step: CGFloat = 14
        let count = Int(tileSize / step)
        let ink = CGColor(gray: 0.09, alpha: opacity)

        ctx.setFillColor(ink)
        for row in 0..<count {
            for col in 0..<count {
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
        tileCache[key] = image
        return image
    }
}
