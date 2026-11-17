import Foundation
import SwiftUI
import Observation

/// 桌面端主题外观模式 (支持跟随系统、暖色棉纸、胶片暗房)
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case paper = "paper"
    case darkroom = "darkroom"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "跟随系统"
        case .paper: return "暖色棉纸"
        case .darkroom: return "暗房安全灯"
        }
    }

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .paper: return .light
        case .darkroom: return .dark
        }
    }
}

/// 桌面端主窗口侧栏导航模块 (对标 Web HeaderNav 6 大平级主视图)
public enum WorkbenchSection: String, CaseIterable, Identifiable, Sendable {
    case stream = "stream"       // 时间流 (home)
    case ledger = "ledger"       // 资产 (transactions)
    case wishes = "wishes"       // 心愿 (wishes)
    case atlas = "atlas"         // 足迹 (atlas)
    case projects = "projects"   // 项目 (projects)
    case dossier = "dossier"     // 主理人 (about)
    case preferences = "preferences" // 偏好设置
    case hub = "hub"             // 中枢与设备
    case about = "about"         // 关于活页

    public var id: String { rawValue }

    /// 六大核心生活内容板块（与 Web HeaderNav 对齐，⌘1–⌘6 绑定到这些）
    public static var contentSections: [WorkbenchSection] {
        [.stream, .ledger, .wishes, .atlas, .projects, .dossier]
    }

    /// 配置类条目（重定向至独立 Settings 窗口）
    public static var configurationSections: [WorkbenchSection] {
        [.preferences, .hub, .about]
    }

    public var title: String {
        switch self {
        case .stream: return "时间流"
        case .ledger: return "资产"
        case .wishes: return "心愿"
        case .atlas: return "足迹"
        case .projects: return "项目"
        case .dossier: return "主理人"
        case .preferences: return "偏好设置"
        case .hub: return "中枢与设备"
        case .about: return "关于活页"
        }
    }

    public var icon: String {
        switch self {
        case .stream: return ArchiveIcon.stream.systemName
        case .ledger: return ArchiveIcon.ledger.systemName
        case .wishes: return ArchiveIcon.wishes.systemName
        case .atlas: return ArchiveIcon.atlas.systemName
        case .projects: return ArchiveIcon.projects.systemName
        case .dossier: return ArchiveIcon.dossier.systemName
        case .preferences: return ArchiveIcon.preferences.systemName
        case .hub: return ArchiveIcon.hub.systemName
        case .about: return ArchiveIcon.about.systemName
        }
    }
}

/// 极速捕捉模式选项 (极速记录 / 快速记账)
public enum QuickCaptureTab: String, CaseIterable, Sendable {
    case thought = "极速记录"
    case ledger = "快速记账"
}

/// 全仓统一中枢连接徽标状态 (唯一事实源：驱动侧栏、设置顶栏、中枢管理与关于页)
public enum HubConnectionBadgeState: Sendable, Equatable {
    case unpaired
    case offline
    case syncFailed(count: Int)
    case syncing
    case pendingUpload(count: Int)
    case online

    public var label: String {
        switch self {
        case .unpaired:
            return "未配对中枢"
        case .offline:
            return "离线发件箱守护"
        case .syncFailed(let count):
            return "同步失败 \(count) 条"
        case .syncing:
            return "同步中…"
        case .pendingUpload(let count):
            return "待同步 \(count) 条"
        case .online:
            return "中枢就绪"
        }
    }

    public var dotColor: Color {
        switch self {
        case .online:
            return ArchivePalette.accentMoss
        case .syncing:
            return ArchivePalette.spectrumStudy
        case .pendingUpload, .offline:
            return ArchivePalette.accentWarm
        case .syncFailed:
            return ArchivePalette.accentWarm
        case .unpaired:
            return ArchivePalette.inkMuted
        }
    }

    /// 辅助功能「不靠颜色区分」开启时配合展示的语义图标形状
    public var symbolName: String {
        switch self {
        case .online: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath.circle.fill"
        case .pendingUpload: return "arrow.up.circle.fill"
        case .offline: return "icloud.slash.fill"
        case .syncFailed: return "exclamationmark.triangle.fill"
        case .unpaired: return "link.badge.plus"
        }
    }
}

/// 跨窗口持久化快速捕捉草稿容器 (@Observable)
/// 统一 MenuBar 与悬浮窗状态实例，消除切换 Tab 与双宿主状态割裂
@Observable
@MainActor
public final class QuickCaptureDraft {
    public var activeTab: QuickCaptureTab = .thought
    // 极速记录草稿
    public var entryType: EntryType = .life
    public var titleText: String = ""
    public var contentText: String = ""
    public var selectedCityCode: String = ""
    public var selectedCityName: String = ""
    public var occurredAt: Date = Date()
    public var showBackdatePicker: Bool = false
    public var isPrivate: Bool = false
    /// 共享相纸装裱队列（MenuBar 与 ⌘⇧L 悬浮窗共用同一上传进度与单张重试状态机）
    let media = EntryMediaState()

    // 快速记账草稿（切换 Tab 或在菜单栏/悬浮窗间切换时完整保留）
    public var ledgerSmartInput: String = ""
    public var ledgerAmountString: String = ""
    public var ledgerTitleString: String = ""
    public var ledgerSelectedType: String = "expense"
    public var ledgerSelectedCategory: String = ""
    public var ledgerSelectedPayment: String = ""
    public var ledgerSelectedCityCode: String = ""
    public var ledgerSelectedCityName: String = ""
    public var ledgerOccurredAt: Date = Date()
    public var ledgerShowDatePicker: Bool = false

    public func resetThought() {
        titleText = ""
        contentText = ""
        selectedCityCode = ""
        selectedCityName = ""
        media.removeAll()
        occurredAt = Date()
        showBackdatePicker = false
        isPrivate = false
    }

    public func resetLedger() {
        ledgerSmartInput = ""
        ledgerAmountString = ""
        ledgerTitleString = ""
        ledgerSelectedType = "expense"
        ledgerOccurredAt = Date()
        ledgerShowDatePicker = false
    }

    public func reset() {
        resetThought()
        resetLedger()
    }
}

/// 全局纸本确认与警示对话框请求 (对标 Web useConfirm.ts / ConfirmDialog.vue)
public struct ConfirmDialogRequest: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String
    public var confirmText: String
    public var cancelText: String
    public var danger: Bool
    public var onConfirm: () -> Void
    public var onCancel: (() -> Void)?

    public init(
        title: String = "请确认",
        message: String,
        confirmText: String = "确认",
        cancelText: String = "取消",
        danger: Bool = true,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.confirmText = confirmText
        self.cancelText = cancelText
        self.danger = danger
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
}
