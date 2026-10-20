import Foundation

/// 应用元信息单一事实源 (Single Source of Truth)
/// 版本号、仓库地址、构建号等常量集中在此，避免在多个视图里各写一份而漂移。
public enum ArchiveAppInfo {
    /// GitHub 仓库地址（About 页、更新检查器、README 均引用此常量）
    public static let repository = "Losse-Leaf/MacOS"
    /// 仓库首页 URL
    public static var repositoryURL: URL? { URL(string: "https://github.com/\(repository)") }
    /// 应用名称
    public static let displayName = "活页集 Loose-Leaf"
    /// 副标题
    public static let subtitle = "个人生活档案馆"

    /// 对外版本号（读取自 Info.plist，缺失时回退到 "0.0.0"）
    public static let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    /// 构建号
    public static let build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    /// 完整版本串（用于展示与比较）
    public static var fullVersion: String { "v\(version) (Build \(build))" }
}
