import SwiftUI
import AppKit

/// 资源 Bundle 定位器（兼容 Xcode App Target 与 SwiftPM 构建）
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
public enum ArchivePalette {
    public static let archivePaper = Color("ArchivePaper", bundle: ArchiveResourceBundle.bundle)
    public static let archiveSubtle = Color("ArchiveSubtle", bundle: ArchiveResourceBundle.bundle)
    public static let inkPrimary = Color("InkPrimary", bundle: ArchiveResourceBundle.bundle)
    public static let inkSecondary = Color("InkSecondary", bundle: ArchiveResourceBundle.bundle)
    public static let inkMuted = Color("InkMuted", bundle: ArchiveResourceBundle.bundle)
    public static let borderSubtle = Color("BorderSubtle", bundle: ArchiveResourceBundle.bundle)
    public static let borderDivider = Color("BorderDivider", bundle: ArchiveResourceBundle.bundle)
    public static let accentWarm = Color("AccentWarm", bundle: ArchiveResourceBundle.bundle)
    public static let accentMoss = Color("AccentMoss", bundle: ArchiveResourceBundle.bundle)

    // 散页原生分类矿物色（与 Vesper Space 四大展区 1:1 对齐，浅/深自适应并通过 WCAG AA 对比度校验）
    public static let tagPhotography = Color("TagPhotography", bundle: ArchiveResourceBundle.bundle)
    public static let tagTravel = Color("TagTravel", bundle: ArchiveResourceBundle.bundle)
    public static let tagStillLife = Color("TagStillLife", bundle: ArchiveResourceBundle.bundle)
    public static let tagMotion = Color("TagMotion", bundle: ArchiveResourceBundle.bundle)

    // 光谱语义色静态缓存（避免视图每次渲染构造 Color(name:bundle:)）
    public static let spectrumDining = Color("SpectrumDining", bundle: ArchiveResourceBundle.bundle)
    public static let spectrumTransit = Color("SpectrumTransit", bundle: ArchiveResourceBundle.bundle)
    public static let spectrumShopping = Color("SpectrumShopping", bundle: ArchiveResourceBundle.bundle)
    public static let spectrumLeisure = Color("SpectrumLeisure", bundle: ArchiveResourceBundle.bundle)
    public static let spectrumHousing = Color("SpectrumHousing", bundle: ArchiveResourceBundle.bundle)
    public static let spectrumStudy = Color("SpectrumStudy", bundle: ArchiveResourceBundle.bundle)
    public static let spectrumMedical = Color("SpectrumMedical", bundle: ArchiveResourceBundle.bundle)
    public static let spectrumOther = Color("SpectrumOther", bundle: ArchiveResourceBundle.bundle)

    private static let spectrumRing: [Color] = [
        spectrumOther, spectrumDining, spectrumTransit, spectrumShopping,
        spectrumLeisure, spectrumHousing, spectrumStudy, spectrumMedical
    ]

    /// 支出类目光谱专用大地色 (docs/web.md §2.3)
    public static func categoryColor(for category: String) -> Color {
        switch category {
        case "餐饮":
            return spectrumDining
        case "交通":
            return spectrumTransit
        case "购物", "数码器材":
            return spectrumShopping
        case "娱乐":
            return spectrumLeisure
        case "住房":
            return spectrumHousing
        case "学习":
            return spectrumStudy
        case "医疗":
            return spectrumMedical
        default:
            let hash = category.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
            return spectrumRing[abs(hash) % spectrumRing.count]
        }
    }
}

public extension EntryCategory {
    /// 散页原生分类对应的纸墨矿物强调色（日常沿用松绿，画廊四区取石青 / 花青 / 赭石 / 青莲）
    var accentColor: Color {
        switch self {
        case .daily: return ArchivePalette.accentMoss
        case .photography: return ArchivePalette.tagPhotography
        case .travel: return ArchivePalette.tagTravel
        case .stillLife: return ArchivePalette.tagStillLife
        case .motion: return ArchivePalette.tagMotion
        }
    }
}

public extension LifeEntry {
    /// 时间流卡片、详情页与检索结果共享的形态 / 分类强调色（全应用唯一事实源）
    var displayAccentColor: Color {
        switch EntryType(rawValue: type) {
        case .wish:
            return ArchivePalette.spectrumLeisure
        case .transaction:
            return ArchivePalette.spectrumDining
        case .life, .none:
            return resolvedCategory.accentColor
        }
    }
}

/// 跨平台排版字体栈映射 (Typography Mapping · A4 原生字体策略)
/// 统一采用 macOS 系统原生光学字族：
/// - 刊头与标题：`New York` (`.serif`) + 系统级联宋体/苹方，零内嵌字体包体积负担，消除 `Songti SC` 劫持西文字符的弊病；
/// - 正文与交互：`SF Pro` (`.default`) + `PingFang SC`；
/// - 刻度与金额：`SF Mono` (`.monospaced`)，强制等宽数字对齐如机械刻度。
public enum ArchiveTypography {
    /// 古典衬线体（Apple 原生 `New York` 光学衬线 + 中文级联，支持系统动态字号缩放）
    public static func editorialSerif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// 现代无衬线正文 (`SF Pro` + `PingFang SC`)
    public static func bodySans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// 等宽数字刻度（Apple 原生 `SF Mono`，强制等宽数字对齐）
    public static func monoScale(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }

    /// 字号阶梯（统一语义，消除魔法字号）
    public enum Scale {
        public static let display: CGFloat = 26       // 刊头主标题
        public static let title: CGFloat = 16         // 弹窗与空态标题
        public static let heading: CGFloat = 13       // 小节标题
        public static let body: CGFloat = 12          // 标准界面正文
        public static let caption: CGFloat = 11       // 辅助说明
        public static let micro: CGFloat = 10         // 元信息（macOS 最小可读字号下限）
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
    public static let quick: Animation = .easeOut(duration: 0.15)
    public static let standard: Animation = .easeInOut(duration: 0.22)
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
public enum ArchiveIcon {
    case stream, ledger, wishes
    case preferences, hub, about
    case entryLife, entryWish, entryTransaction
    case search, sync, add, edit, delete, detail, close, location
    case export, camera, lock, cloud

    public var systemName: String {
        switch self {
        case .stream: return "book.pages"
        case .ledger: return "chart.bar.doc.horizontal"
        case .wishes: return "sparkles"
        case .preferences: return "slider.horizontal.3"
        case .hub: return "laptopcomputer.and.iphone"
        case .about: return "info.circle"
        case .entryLife: return "leaf"
        case .entryWish: return "sparkles"
        case .entryTransaction: return "creditcard"
        case .search: return "magnifyingglass"
        case .sync: return "arrow.clockwise"
        case .add: return "plus"
        case .edit: return "square.and.pencil"
        case .delete: return "trash"
        case .detail: return "arrow.up.left.and.arrow.down.right"
        case .close: return "xmark"
        case .location: return "mappin"
        case .export: return "square.and.arrow.up"
        case .camera: return "camera"
        case .lock: return "lock"
        case .cloud: return "icloud"
        }
    }
}
