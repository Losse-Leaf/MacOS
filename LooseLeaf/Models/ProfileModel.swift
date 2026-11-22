import Foundation

/// 主理人身份档案 (CuratorProfile)
/// 严格遵守：全数据后端动态下发，空态优先，严禁在客户端硬编码人名、地名或版权信息
public struct CuratorProfile: Codable, Equatable, Sendable {
    public var name: String
    public var title: String
    public var bio: String
    public var location: String
    public var currentCity: String
    public var avatarUrl: String
    public var avatarKey: String?
    public var motto: String
    public var manifesto: String
    public var email: String?
    public var github: String?
    public var socialLinks: [String: String]?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case bio
        case location
        case currentCity = "current_city"
        case avatarUrl = "avatar_url"
        case avatarKey = "avatar_key"
        case motto
        case manifesto
        case email
        case github
        case socialLinks = "social_links"
        case updatedAt = "updated_at"
    }

    public init(
        name: String = "",
        title: String = "",
        bio: String = "",
        location: String = "",
        currentCity: String = "",
        avatarUrl: String = "",
        avatarKey: String? = nil,
        motto: String = "",
        manifesto: String = "",
        email: String? = nil,
        github: String? = nil,
        socialLinks: [String: String]? = nil,
        updatedAt: String? = nil
    ) {
        self.name = name
        self.title = title
        self.bio = bio
        self.location = location
        self.currentCity = currentCity
        self.avatarUrl = avatarUrl
        self.avatarKey = avatarKey
        self.motto = motto
        self.manifesto = manifesto
        self.email = email
        self.github = github
        self.socialLinks = socialLinks
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        bio = (try? container.decode(String.self, forKey: .bio)) ?? ""
        location = (try? container.decode(String.self, forKey: .location)) ?? ""
        currentCity = (try? container.decode(String.self, forKey: .currentCity)) ?? ""
        avatarUrl = (try? container.decode(String.self, forKey: .avatarUrl)) ?? ""
        avatarKey = try? container.decodeIfPresent(String.self, forKey: .avatarKey)
        motto = (try? container.decode(String.self, forKey: .motto)) ?? ""
        manifesto = (try? container.decode(String.self, forKey: .manifesto)) ?? ""
        email = try? container.decodeIfPresent(String.self, forKey: .email)
        github = try? container.decodeIfPresent(String.self, forKey: .github)
        socialLinks = try? container.decodeIfPresent([String: String].self, forKey: .socialLinks)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// 动态展示当前所在地点（优先 current_city，回退 location，为空则返回空字符串）
    public var displayCity: String {
        if !currentCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return currentCity
        }
        return location
    }
}

/// 更新主理人档案请求载荷 (PUT /api/v1/profile)
public struct UpdateProfileRequest: Codable, Sendable {
    public var name: String?
    public var title: String?
    public var bio: String?
    public var location: String?
    public var currentCity: String?
    public var avatarKey: String?
    public var motto: String?
    public var manifesto: String?
    public var email: String?
    public var github: String?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case bio
        case location
        case currentCity = "current_city"
        case avatarKey = "avatar_key"
        case motto
        case manifesto
        case email
        case github
    }

    public init(
        name: String? = nil,
        title: String? = nil,
        bio: String? = nil,
        location: String? = nil,
        currentCity: String? = nil,
        avatarKey: String? = nil,
        motto: String? = nil,
        manifesto: String? = nil,
        email: String? = nil,
        github: String? = nil
    ) {
        self.name = name
        self.title = title
        self.bio = bio
        self.location = location
        self.currentCity = currentCity
        self.avatarKey = avatarKey
        self.motto = motto
        self.manifesto = manifesto
        self.email = email
        self.github = github
    }
}

/// 站点全局配置 (SiteConfig, GET /api/v1/config)
public struct SiteConfig: Codable, Equatable, Sendable {
    public var siteName: String
    public var siteSubtitle: String?
    public var siteDesc: String?
    public var curatorName: String
    public var defaultLocation: String
    public var initialized: Bool

    enum CodingKeys: String, CodingKey {
        case siteName = "site_name"
        case siteSubtitle = "site_subtitle"
        case siteDesc = "site_desc"
        case curatorName = "curator_name"
        case defaultLocation = "default_location"
        case initialized
    }

    public init(
        siteName: String = "",
        siteSubtitle: String? = nil,
        siteDesc: String? = nil,
        curatorName: String = "",
        defaultLocation: String = "",
        initialized: Bool = false
    ) {
        self.siteName = siteName
        self.siteSubtitle = siteSubtitle
        self.siteDesc = siteDesc
        self.curatorName = curatorName
        self.defaultLocation = defaultLocation
        self.initialized = initialized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        siteName = (try? container.decode(String.self, forKey: .siteName)) ?? ""
        siteSubtitle = try? container.decodeIfPresent(String.self, forKey: .siteSubtitle)
        siteDesc = try? container.decodeIfPresent(String.self, forKey: .siteDesc)
        curatorName = (try? container.decode(String.self, forKey: .curatorName)) ?? ""
        defaultLocation = (try? container.decode(String.self, forKey: .defaultLocation)) ?? ""
        initialized = (try? container.decode(Bool.self, forKey: .initialized)) ?? false
    }
}

/// 系统初始化状态探针 (GET /api/v1/system/status)
public struct SystemStatus: Codable, Equatable, Sendable {
    public var initialized: Bool
    public var siteName: String
    public var curatorName: String
    public var oidcEnabled: Bool
    public var oidcProviderName: String?

    enum CodingKeys: String, CodingKey {
        case initialized
        case siteName = "site_name"
        case curatorName = "curator_name"
        case oidcEnabled = "oidc_enabled"
        case oidcProviderName = "oidc_provider_name"
    }

    public init(
        initialized: Bool = false,
        siteName: String = "",
        curatorName: String = "",
        oidcEnabled: Bool = false,
        oidcProviderName: String? = nil
    ) {
        self.initialized = initialized
        self.siteName = siteName
        self.curatorName = curatorName
        self.oidcEnabled = oidcEnabled
        self.oidcProviderName = oidcProviderName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        initialized = (try? container.decode(Bool.self, forKey: .initialized)) ?? false
        siteName = (try? container.decode(String.self, forKey: .siteName)) ?? ""
        curatorName = (try? container.decode(String.self, forKey: .curatorName)) ?? ""
        oidcEnabled = (try? container.decode(Bool.self, forKey: .oidcEnabled)) ?? false
        oidcProviderName = try? container.decodeIfPresent(String.self, forKey: .oidcProviderName)
    }
}
