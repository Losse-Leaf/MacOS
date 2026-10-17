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
/// 注：本文件位于 Models 层（供 Widget 扩展共享编译），禁止在此引入 AppKit 视图类型。
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
    private static let hasNewsreader: Bool = NSFont(name: "Newsreader", size: 12) != nil
    private static let hasSongti: Bool = NSFont(name: "Songti SC", size: 12) != nil
    private static let hasJetBrainsMono: Bool = NSFont(name: "JetBrains Mono", size: 12) != nil

    /// 古典衬线体 (Newsreader -> Songti SC -> Baskerville -> System Serif)
    public static func editorialSerif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if hasNewsreader {
            return .custom("Newsreader", size: size).weight(weight)
        }
        if hasSongti {
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
        if hasJetBrainsMono {
            return .custom("JetBrains Mono", size: size).weight(weight).monospacedDigit()
        }
        return .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }
}

/// 统一圆角系统阶梯 (Corner Radii Scale)
public enum ArchiveRadius {
    public static let xs: CGFloat = 4   // 极小徽标
    public static let sm: CGFloat = 6   // 胶囊、按钮、输入框、微控件
    public static let md: CGFloat = 10  // 标准日记卡片、面板
    public static let lg: CGFloat = 14  // 模态弹窗、主工作区
}

/// 纸张物理微投影修饰符（取代死板 0.5pt 灰色硬边框）
public struct PaperElevationModifier: ViewModifier {
    public var level: Int

    public func body(content: Content) -> some View {
        switch level {
        case 1:
            content
                .shadow(color: Color.black.opacity(0.025), radius: 1, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.035), radius: 6, x: 0, y: 2)
        case 2:
            content
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 2)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        default:
            content
        }
    }
}

public extension View {
    /// 纸张物理轻微投影
    func paperElevation(_ level: Int = 1) -> some View {
        modifier(PaperElevationModifier(level: level))
    }
}
