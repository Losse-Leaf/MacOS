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
/// 浅色模式自适应棉纸黑墨纤维；暗房模式自适应银盐感光微晶 (Silver Grain)。
private struct PaperGrainCanvas: View {
    @Environment(\.colorScheme) private var colorScheme
    let opacity: Double

    var body: some View {
        let isDark = colorScheme == .dark
        if let tile = PaperGrainTileCache.tileImage(opacity: opacity, isDark: isDark) {
            Image(decorative: tile, scale: 2)
                .resizable(resizingMode: .tile)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }
}

/// 纸纹 256x256 硬件瓦片缓存（同透明度只生成一次，内存占用 < 0.25MB）
/// 并发策略：
/// - 命中路径：只做一次字典查询（临界区极短），不进入绘制队列、不发生阻塞
/// - 未命中路径：在专用串行队列上生成瓦片（双检），绘制期间**不持有缓存锁**，
///   其它等待者不会被 CGContext 绘制阻塞；生成完成后再写回缓存
private enum PaperGrainTileCache {
    /// 缓存容器：锁只保护极短的读写片段，绝不包裹 CGContext 绘制
    private static let store = TileStore()

    /// 专用串行队列：瓦片生成串行执行，避免同一 key 被重复绘制
    private static let renderQueue = DispatchQueue(
        label: "com.looseleaf.paper.grain.render",
        qos: .userInitiated
    )

    static func tileImage(opacity: Double, isDark: Bool = false) -> CGImage? {
        let key = cacheKey(opacity: opacity, isDark: isDark)

        // 快路径：命中即返回，不触碰绘制队列
        if let hit = store.image(forKey: key) {
            return hit
        }

        // 慢路径：双检后在专用队列生成（绘制全程不持锁）
        return renderQueue.sync {
            if let hit = store.image(forKey: key) {
                return hit
            }
            guard let image = renderTile(opacity: opacity, isDark: isDark) else { return nil }
            store.setImage(image, forKey: key)
            return image
        }
    }

    private static func cacheKey(opacity: Double, isDark: Bool) -> String {
        "\(isDark ? "dark" : "light")_\((opacity * 1000).rounded() / 1000)"
    }

    /// 瓦片绘制：仅在专用串行队列上调用，禁止在持锁状态下执行
    private static func renderTile(opacity: Double, isDark: Bool) -> CGImage? {
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

        // 浅色模式为宣纸黑墨纤维 (Dark Ink)；深色模式为银盐感光微晶 (Silver Grain / Halide Crystals)
        let ink = isDark
            ? CGColor(gray: 0.88, alpha: opacity * 1.35)
            : CGColor(gray: 0.10, alpha: opacity)

        ctx.setFillColor(ink)
        for row in 0..<count {
            for col in 0..<count {
                let hash = UInt64((row &* 73856093) ^ (col &* 19349663))
                if hash % 3 == 0 {
                    let offsetX = CGFloat((hash >> 3) % 11)
                    let offsetY = CGFloat((hash >> 7) % 11)
                    let dotSize: CGFloat = (hash % 2 == 0) ? 1.05 : 0.7
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

        return ctx.makeImage()
    }

    /// 瓦片缓存容器：读写片段极短，绘制不经过此处
    private final class TileStore: @unchecked Sendable {
        private let lock = NSLock()
        private var images: [String: CGImage] = [:]

        func image(forKey key: String) -> CGImage? {
            lock.lock()
            defer { lock.unlock() }
            return images[key]
        }

        func setImage(_ image: CGImage, forKey key: String) {
            lock.lock()
            images[key] = image
            lock.unlock()
        }
    }
}
