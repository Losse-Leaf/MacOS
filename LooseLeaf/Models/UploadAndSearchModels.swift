import Foundation

// MARK: - 媒体预签名上传、器材转让与检索聚合载荷

public struct PresignUploadRequest: Codable, Sendable {
    public var filename: String
    public var contentType: String
    public var size: Int64

    enum CodingKeys: String, CodingKey {
        case filename
        case contentType = "content_type"
        case size
    }

    public init(filename: String, contentType: String, size: Int64) {
        self.filename = filename
        self.contentType = contentType
        self.size = size
    }
}

public struct PresignUploadResponse: Codable, Sendable {
    public var uploadId: String
    public var objectKey: String
    public var uploadUrl: String
    public var expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case uploadId = "upload_id"
        case objectKey = "object_key"
        case uploadUrl = "upload_url"
        case expiresIn = "expires_in"
    }
}

public struct CompleteUploadRequest: Codable, Sendable {
    public var uploadId: String
    public var objectKey: String
    public var originalFilename: String
    public var mimeType: String
    public var size: Int64
    public var width: Int
    public var height: Int

    enum CodingKeys: String, CodingKey {
        case uploadId = "upload_id"
        case objectKey = "object_key"
        case originalFilename = "original_filename"
        case mimeType = "mime_type"
        case size
        case width
        case height
    }

    public init(
        uploadId: String,
        objectKey: String,
        originalFilename: String,
        mimeType: String,
        size: Int64,
        width: Int,
        height: Int
    ) {
        self.uploadId = uploadId
        self.objectKey = objectKey
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.size = size
        self.width = width
        self.height = height
    }
}

public struct UnifiedUploadResponse: Codable, Sendable {
    public var objectKey: String
    public var url: String
    public var expiresIn: Int
    public var filename: String
    public var mimeType: String
    public var size: Int64
    public var width: Int?
    public var height: Int?
    public var attachmentId: Int
    /// 缩略图地址（中枢自己的路由；缺省时客户端退回原图）
    public var thumbnailUrl: String?

    enum CodingKeys: String, CodingKey {
        case objectKey = "object_key"
        case url
        case thumbnailUrl = "thumbnail_url"
        case expiresIn = "expires_in"
        case filename
        case mimeType = "mime_type"
        case size
        case width
        case height
        case attachmentId = "attachment_id"
    }
}

/// 随身器材转售回血请求 (POST /api/v1/assets/gear/:id/sell)
public struct SellGearRequest: Codable, Sendable {
    public var soldPriceCents: Int64
    public var soldDate: String
    public var note: String?

    enum CodingKeys: String, CodingKey {
        case soldPriceCents = "sold_price_cents"
        case soldDate = "sold_date"
        case note
    }

    public init(
        soldPriceCents: Int64,
        soldDate: String = FormatUtils.beijingDateString(),
        note: String? = nil
    ) {
        self.soldPriceCents = soldPriceCents
        self.soldDate = soldDate
        self.note = note
    }
}

public struct OnThisDayResponse: Codable, Equatable, Sendable {
    public var month: Int
    public var day: Int
    public var entries: [LifeEntry]

    public init(month: Int = 1, day: Int = 1, entries: [LifeEntry] = []) {
        self.month = month
        self.day = day
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = (try? container.decode(Int.self, forKey: .month)) ?? 1
        day = (try? container.decode(Int.self, forKey: .day)) ?? 1
        entries = (try? container.decodeIfPresent([LifeEntry].self, forKey: .entries)) ?? []
    }
}

public struct GlobalSearchResponse: Codable, Equatable, Sendable {
    public var query: String
    public var entries: [LifeEntry]
    public var footprints: [Footprint]
    public var wishes: [Wish]
    public var projects: [Project]

    public init(
        query: String = "",
        entries: [LifeEntry] = [],
        footprints: [Footprint] = [],
        wishes: [Wish] = [],
        projects: [Project] = []
    ) {
        self.query = query
        self.entries = entries
        self.footprints = footprints
        self.wishes = wishes
        self.projects = projects
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = (try? container.decode(String.self, forKey: .query)) ?? ""
        entries = (try? container.decodeIfPresent([LifeEntry].self, forKey: .entries)) ?? []
        footprints = (try? container.decodeIfPresent([Footprint].self, forKey: .footprints)) ?? []
        wishes = (try? container.decodeIfPresent([Wish].self, forKey: .wishes)) ?? []
        projects = (try? container.decodeIfPresent([Project].self, forKey: .projects)) ?? []
    }
}

/// 分类字典包裹响应（兼容 `{items:[...]}` 形态）
public struct CategoriesListEnvelope: Codable, Sendable {
    public var items: [CategoryOption]?
}
