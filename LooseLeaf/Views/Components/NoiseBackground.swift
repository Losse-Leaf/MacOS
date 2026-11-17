import SwiftUI
import AppKit

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

/// 微噪点纸面材质背景组件
/// 优化：适配 `accessibilityReduceTransparency`，`224×224` 整除步长无接缝平铺，后台异步预热生成零主线程阻塞
public struct NoiseBackground: View {
    public var useSubtleSurface: Bool
    public var enableVibrancy: Bool
    public var grainOpacity: Double

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
        let shouldUseVibrancy = enableVibrancy && !reduceTransparency
        return ZStack {
            if shouldUseVibrancy {
                WindowVibrancyView()
                    .opacity(0.35)
            }

            (useSubtleSurface ? ArchivePalette.archiveSubtle : ArchivePalette.archivePaper)
                .opacity(shouldUseVibrancy ? 0.94 : 1.0)

            if !reduceTransparency && grainOpacity > 0 {
                PaperGrainCanvas(opacity: grainOpacity)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

private struct PaperGrainCanvas: View {
    @Environment(\.colorScheme) private var colorScheme
    let opacity: Double
    @State private var loadedTile: CGImage?

    var body: some View {
        let isDark = colorScheme == .dark
        let cached = PaperGrainTileCache.cachedTileImage(opacity: opacity, isDark: isDark) ?? loadedTile
        return Group {
            if let tile = cached {
                Image(decorative: tile, scale: 2)
                    .resizable(resizingMode: .tile)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .task(id: "\(isDark)_\(opacity)") {
            if PaperGrainTileCache.cachedTileImage(opacity: opacity, isDark: isDark) == nil {
                loadedTile = await PaperGrainTileCache.loadTileImageAsync(opacity: opacity, isDark: isDark)
            }
        }
    }
}

private enum PaperGrainTileCache {
    private static let store: TileStore = {
        let s = TileStore()
        DispatchQueue.global(qos: .utility).async {
            for isDark in [false, true] {
                let key = cacheKey(opacity: 0.03, isDark: isDark)
                if s.image(forKey: key) == nil, let img = renderTile(opacity: 0.03, isDark: isDark) {
                    s.setImage(img, forKey: key)
                }
            }
        }
        return s
    }()

    private static let renderQueue = DispatchQueue(
        label: "com.looseleaf.paper.grain.render",
        qos: .utility
    )

    static func cachedTileImage(opacity: Double, isDark: Bool) -> CGImage? {
        store.image(forKey: cacheKey(opacity: opacity, isDark: isDark))
    }

    static func loadTileImageAsync(opacity: Double, isDark: Bool) async -> CGImage? {
        let key = cacheKey(opacity: opacity, isDark: isDark)
        if let hit = store.image(forKey: key) { return hit }
        return await withCheckedContinuation { continuation in
            renderQueue.async {
                if let hit = store.image(forKey: key) {
                    continuation.resume(returning: hit)
                    return
                }
                let img = renderTile(opacity: opacity, isDark: isDark)
                if let img { store.setImage(img, forKey: key) }
                continuation.resume(returning: img)
            }
        }
    }

    private static func cacheKey(opacity: Double, isDark: Bool) -> String {
        "\(isDark ? "dark" : "light")_\((opacity * 1000).rounded() / 1000)"
    }

    private static func renderTile(opacity: Double, isDark: Bool) -> CGImage? {
        let tileSize: CGFloat = 224
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
