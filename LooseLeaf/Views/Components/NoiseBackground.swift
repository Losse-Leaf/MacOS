import SwiftUI
import AppKit

// 注：语义色盘 (ArchivePalette)、字体令牌 (ArchiveTypography) 与资源 Bundle 定位器
// 已抽出至 Models/ArchiveTokens.swift（供 Widget 扩展等共享编译）。

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

/// 零外部依赖的 Canvas 纸本微噪点纹理层
private struct PaperGrainCanvas: View {
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 14
            let cols = Int(size.width / step) + 1
            let rows = Int(size.height / step) + 1
            let inkColor = ArchivePalette.inkPrimary.opacity(opacity)

            for row in 0..<rows {
                for col in 0..<cols {
                    let hash = UInt64((row &* 73856093) ^ (col &* 19349663))
                    if hash % 3 == 0 {
                        let offsetX = CGFloat((hash >> 3) % 11)
                        let offsetY = CGFloat((hash >> 7) % 11)
                        let x = CGFloat(col) * step + offsetX
                        let y = CGFloat(row) * step + offsetY
                        let dotSize: CGFloat = (hash % 2 == 0) ? 1.1 : 0.75
                        let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                        context.fill(Path(ellipseIn: rect), with: .color(inkColor))
                    }
                }
            }
        }
    }
}
