import Foundation

// MARK: - 造物项目状态语义与数据模型 (Project Status & Models)

/// 造物项目状态语义字典（全应用唯一真源）。
/// 四端统一为中文四态（与后端 validProjectStatuses 白名单一致）；
/// 存量英文/历史表述由 normalize 兼容读取。
public enum ProjectStatus: String, CaseIterable, Identifiable, Sendable {
    case inProgress = "进行中"
    case completed = "已完成"
    case maintaining = "维护中"
    case shelved = "已搁置"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public static func normalize(_ raw: String?) -> ProjectStatus {
        guard let raw, !raw.isEmpty else { return .inProgress }
        if let matched = ProjectStatus(rawValue: raw) {
            return matched
        }
        switch raw.lowercased() {
        case "active", "wip": return .inProgress
        case "maintained", "持续维护": return .maintaining
        case "archived", "已归档": return .shelved
        default: return .inProgress
        }
    }

    public static func matches(_ raw: String?, selected: String) -> Bool {
        if selected == "all" { return true }
        return normalize(raw).rawValue == selected
    }
}

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var subtitle: String?
    public var description: String
    public var story: String?
    public var category: String?
    public var githubUrl: String?
    public var status: String?
    public var order: Int?
    public var isPrivate: Bool?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case description
        case story
        case category
        case githubUrl = "github_url"
        case status
        case order
        case isPrivate = "is_private"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: Int,
        title: String,
        subtitle: String? = nil,
        description: String,
        story: String? = nil,
        category: String? = nil,
        githubUrl: String? = nil,
        status: String? = ProjectStatus.inProgress.rawValue,
        order: Int? = 0,
        isPrivate: Bool? = false,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.story = story
        self.category = category
        self.githubUrl = githubUrl
        self.status = status
        self.order = order
        self.isPrivate = isPrivate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 新建或修改造物项目请求 (POST / PUT /api/v1/projects)
public struct CreateProjectRequest: Codable, Sendable {
    public var title: String
    public var subtitle: String?
    public var description: String
    /// 项目故事（设计手记）
    public var story: String?
    public var category: String?
    public var status: String?
    public var githubUrl: String?
    /// 展示顺序（数值小的靠前；为 nil 时不携带该字段，保持服务端原值）
    public var order: Int?
    public var isPrivate: Bool?

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case description
        case story
        case category
        case status
        case githubUrl = "github_url"
        case order
        case isPrivate = "is_private"
    }

    public init(
        title: String,
        subtitle: String? = nil,
        description: String,
        story: String? = nil,
        category: String? = "开源项目",
        status: String? = ProjectStatus.inProgress.rawValue,
        githubUrl: String? = nil,
        order: Int? = nil,
        isPrivate: Bool? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.story = story
        self.category = category
        self.status = status
        self.githubUrl = githubUrl
        self.order = order
        self.isPrivate = isPrivate
    }
}
