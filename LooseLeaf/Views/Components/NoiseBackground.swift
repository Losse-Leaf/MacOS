import SwiftUI
import AppKit

/// 资源 Bundle 定位器（兼容 Xcode App Target、Widget Extension 与 SwiftPM 构建）
public enum ArchiveResourceBundle {
    public static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }
}

/// 自然大地色盘语义令牌绑定 (Earthy Palette Semantic Tokens)
/// 严格遵循 docs/ecosystem.md §4.2 强制约定：
/// 原生端不得在代码中直接书写十六进制色值，统一通过语义名引用 Assets.xcassets
public enum ArchivePalette {
    public static var archivePaper: Color { Color("ArchivePaper", bundle: ArchiveResourceBundle.bundle) }
    public static var archiveSubtle: Color { Color("ArchiveSubtle", bundle: ArchiveResourceBundle.bundle) }
    public static var inkPrimary: Color { Color("InkPrimary", bundle: ArchiveResourceBundle.bundle) }
    public static var inkSecondary: Color { Color("InkSecondary", bundle: ArchiveResourceBundle.bundle) }
    public static var inkMuted: Color { Color("InkMuted", bundle: ArchiveResourceBundle.bundle) }
    public static var borderSubtle: Color { Color("BorderSubtle", bundle: ArchiveResourceBundle.bundle) }
    public static var borderDivider: Color { Color("BorderDivider", bundle: ArchiveResourceBundle.bundle) }
    public static var accentWarm: Color { Color("AccentWarm", bundle: ArchiveResourceBundle.bundle) }
    public static var accentMoss: Color { Color("AccentMoss", bundle: ArchiveResourceBundle.bundle) }

    /// 支出类目光谱专用大地色 (docs/web.md §2.3)
    public static func categoryColor(for category: String) -> Color {
        switch category {
        case "餐饮":
            return Color("SpectrumDining", bundle: ArchiveResourceBundle.bundle)
        case "交通":
            return Color("SpectrumTransit", bundle: ArchiveResourceBundle.bundle)
        case "购物", "数码器材":
            return Color("SpectrumShopping", bundle: ArchiveResourceBundle.bundle)
        case "娱乐":
            return Color("SpectrumLeisure", bundle: ArchiveResourceBundle.bundle)
        case "住房":
            return Color("SpectrumHousing", bundle: ArchiveResourceBundle.bundle)
        case "学习":
            return Color("SpectrumStudy", bundle: ArchiveResourceBundle.bundle)
        case "医疗":
            return Color("SpectrumMedical", bundle: ArchiveResourceBundle.bundle)
        default:
            return Color("SpectrumOther", bundle: ArchiveResourceBundle.bundle)
        }
    }
}

/// 跨平台排版字体栈映射 (Typography Mapping, docs/ecosystem.md §4.3 & docs/macos.md §6.3)
public enum ArchiveTypography {
    /// 古典衬线体 (Newsreader -> Songti SC -> Baskerville -> System Serif)
    public static func editorialSerif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "Newsreader", size: size) != nil {
            return .custom("Newsreader", size: size).weight(weight)
        }
        if NSFont(name: "Songti SC", size: size) != nil {
            return .custom("Songti SC", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    /// 现代无衬线正文 (SF Pro Text -> PingFang SC)
    public static func bodySans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// 等宽数字刻度 (JetBrains Mono -> SF Mono, 强制等宽数字对齐如机械刻度)
    public static func monoScale(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "JetBrains Mono", size: size) != nil {
            return .custom("JetBrains Mono", size: size).weight(weight).monospacedDigit()
        }
        return .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }
}

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
