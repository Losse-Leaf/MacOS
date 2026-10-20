import SwiftUI
import AppKit

/// 资源 Bundle 定位器（兼容 Xcode App Target、Widget Extension 与 SwiftPM 构建）
public enum ArchiveResourceBundle {
    public static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }()
}

/// 自然大地色盘语义令牌绑定 (Earthy Palette Semantic Tokens)
/// 严格遵循 docs/ecosystem.md §4.2 强制约定：
/// 原生端不得在代码中直接书写十六进制色值，统一通过语义名引用 Assets.xcassets
/// 注：本文件位于 Models 层（供 Widget 扩展共享编译），只允许 SwiftUI 色彩/字体令牌与
/// AppKit 的 NSFont 探测，不要放任何 View / ViewModifier。
public enum ArchivePalette {
    // 命名资源色（Color(named:)）本身即动态色，缓存为 static let 后仍会随系统外观变化正确刷新。
    public static let archivePaper = Color("ArchivePaper", bundle: ArchiveResourceBundle.bundle)
    public static let archiveSubtle = Color("ArchiveSubtle", bundle: ArchiveResourceBundle.bundle)
    public static let inkPrimary = Color("InkPrimary", bundle: ArchiveResourceBundle.bundle)
    public static let inkSecondary = Color("InkSecondary", bundle: ArchiveResourceBundle.bundle)
    public static let inkMuted = Color("InkMuted", bundle: ArchiveResourceBundle.bundle)
    public static let borderSubtle = Color("BorderSubtle", bundle: ArchiveResourceBundle.bundle)
    public static let borderDivider = Color("BorderDivider", bundle: ArchiveResourceBundle.bundle)
    public static let accentWarm = Color("AccentWarm", bundle: ArchiveResourceBundle.bundle)
    public static let accentMoss = Color("AccentMoss", bundle: ArchiveResourceBundle.bundle)

    /// 支出类目光谱专用大地色 (docs/web.md §2.3)
    /// 未在语义表中命中的动态分类按序号取色，避免全部落到对比度最低的 SpectrumOther。
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
            return spectrumFallbackColor(for: category)
        }
    }

    /// 动态分类的兜底配色：按名称稳定散列到光谱色盘（保证同一分类每次颜色一致）
    private static func spectrumFallbackColor(for category: String) -> Color {
        let palette = [
            "SpectrumOther", "SpectrumDining", "SpectrumTransit", "SpectrumShopping",
            "SpectrumLeisure", "SpectrumHousing", "SpectrumStudy", "SpectrumMedical"
        ]
        let hash = category.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let name = palette[abs(hash) % palette.count]
        return Color(name, bundle: ArchiveResourceBundle.bundle)
    }
}

/// 跨平台排版字体栈映射 (Typography Mapping, docs/ecosystem.md §4.3 & docs/macos.md §6.3)
public enum ArchiveTypography {
    private static let hasNewsreader: Bool = NSFont(name: "Newsreader", size: 12) != nil
    private static let hasSongti: Bool = NSFont(name: "Songti SC", size: 12) != nil
    private static let hasJetBrainsMono: Bool = NSFont(name: "JetBrains Mono", size: 12) != nil

    /// 古典衬线体 (Newsreader -> Songti SC -> Baskerville -> System Serif)
    /// 使用 `relativeTo: .body` 以支持系统「文本大小」动态缩放（无障碍要求）。
    public static func editorialSerif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if hasNewsreader {
            return .custom("Newsreader", size: size, relativeTo: .body).weight(weight)
        }
        if hasSongti {
            return .custom("Songti SC", size: size, relativeTo: .body).weight(weight)
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
            return .custom("JetBrains Mono", size: size, relativeTo: .body).weight(weight).monospacedDigit()
        }
        return .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }

    /// 字号阶梯（统一语义，避免散落魔法数字）
    public enum Scale {
        public static let display: CGFloat = 26      // 刊头主标题
        public static let title: CGFloat = 16        // 空态标题
        public static let heading: CGFloat = 13      // 小节标题
        public static let body: CGFloat = 12         // 正文
        public static let caption: CGFloat = 11      // 辅助说明
        public static let micro: CGFloat = 10        // 元信息（macOS 最小可读字号）
    }
}

/// 统一圆角系统阶梯 (Corner Radii Scale)
public enum ArchiveRadius {
    public static let xs: CGFloat = 4   // 极小徽标
    public static let sm: CGFloat = 6   // 胶囊、按钮、输入框、微控件
    public static let md: CGFloat = 10  // 标准日记卡片、面板
    public static let lg: CGFloat = 14  // 模态弹窗、主工作区
}

/// 统一间距阶梯 (Spacing Scale)
public enum ArchiveSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

/// 命中区域下限 (Hit Target)
/// - `minPointer`: macOS 指针设备的最小舒适点击区
/// - `minTouch`: 触控板 / 辅助功能 / 触屏场景的最小命中区
public enum ArchiveHitTarget {
    public static let minPointer: CGFloat = 28
    public static let minTouch: CGFloat = 44
}

/// 弹窗宽度阶梯 (Sheet Width)
public enum ArchiveSheetWidth {
    public static let compact: CGFloat = 400
    public static let standard: CGFloat = 480
    public static let wide: CGFloat = 640
    public static let form: CGFloat = 720
}

/// 卡片统一内边距与圆角
public enum ArchiveCardMetrics {
    public static let padding: CGFloat = 14
    public static let radius: CGFloat = ArchiveRadius.sm
}

/// 动效节奏表 (Motion Tokens)
public enum ArchiveMotion {
    public static let instant: Animation = .easeOut(duration: 0.08)
    public static let quick: Animation = .easeOut(duration: 0.15)
    public static let standard: Animation = .easeInOut(duration: 0.22)
    public static let gentle: Animation = .easeInOut(duration: 0.32)
}

/// 层级与投影规范 (Elevation)
public enum ArchiveElevation {
    public static let level0ShadowOpacity: Double = 0
    public static let level1ShadowOpacity: Double = 0.08
    public static let level2ShadowOpacity: Double = 0.14
    public static let level3ShadowOpacity: Double = 0.28

    public static let level1Radius: CGFloat = 2
    public static let level2Radius: CGFloat = 6
    public static let level3Radius: CGFloat = 18
}

/// 图标语义字典 (Iconography)
/// 全应用只引用本枚举，避免同一语义在不同模块使用不同 SF Symbol。
public enum ArchiveIcon {
    case stream, ledger, wishes, atlas, projects, dossier
    case preferences, hub, storage, categories, about, darkroom
    case entryLife, entryTravel, entryProject, entryWish, entryTransaction
    case search, sync, add, edit, delete, featured, detail, close, location
    case export, gear, camera, lock, cloud

    public var systemName: String {
        switch self {
        case .stream: return "book.pages"
        case .ledger: return "chart.bar.doc.horizontal"
        case .wishes: return "sparkles"
        case .atlas: return "map"
        case .projects: return "hammer"
        case .dossier: return "person.text.rectangle"
        case .preferences: return "slider.horizontal.3"
        case .hub: return "laptopcomputer.and.iphone"
        case .storage: return "archivebox"
        case .categories: return "tag"
        case .about: return "info.circle"
        case .darkroom: return "camera.aperture"
        case .entryLife: return "leaf"
        case .entryTravel: return "map"
        case .entryProject: return "hammer"
        case .entryWish: return "sparkles"
        case .entryTransaction: return "creditcard"
        case .search: return "magnifyingglass"
        case .sync: return "arrow.clockwise"
        case .add: return "plus"
        case .edit: return "square.and.pencil"
        case .delete: return "trash"
        case .featured: return "star"
        case .detail: return "arrow.up.left.and.arrow.down.right"
        case .close: return "xmark"
        case .location: return "mappin"
        case .export: return "square.and.arrow.up"
        case .gear: return "shippingbox"
        case .camera: return "camera"
        case .lock: return "lock"
        case .cloud: return "icloud"
        }
    }
}
