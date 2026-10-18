import Foundation

/// 中枢系统级全量备份快照实体 (ServerBackupItem)
/// 严格对应后端 Go 结构体：
/// GET /api/v1/system/backup/list
/// POST /api/v1/system/backup/now
/// DELETE /api/v1/system/backup/:filename
public struct ServerBackupItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String { filename }
    public let filename: String
    public let size: Int64
    public let createdAt: String
    public let storageType: String // "r2" or "local"

    enum CodingKeys: String, CodingKey {
        case filename
        case size
        case createdAt = "created_at"
        case storageType = "storage_type"
    }

    public init(filename: String, size: Int64, createdAt: String, storageType: String) {
        self.filename = filename
        self.size = size
        self.createdAt = createdAt
        self.storageType = storageType
    }

    public var storageTypeBadge: String {
        switch storageType.lowercased() {
        case "r2": return "Cloudflare R2"
        case "local": return "中枢本地磁盘"
        default: return storageType
        }
    }

    public var formattedSize: String {
        let kb = Double(size) / 1024.0
        if kb < 1024.0 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        return String(format: "%.2f MB", mb)
    }

    public var formattedDate: String {
        FormatUtils.parseOccurredDate(createdAt).dotDateTime
    }
}

/// 恢复备份快照响应
public struct RestoreBackupResponse: Codable, Sendable {
    public let message: String?
    public let filename: String?
    public let size: Int64?
}

/// 后端云端对象存储运行状态模型
public struct StorageStatus: Codable, Sendable {
    public let provider: String?
    public let configured: Bool
    public let accountId: String?
    public let bucket: String?
    public let publicDomain: String?
    public let endpoint: String?
    public let accessKeyId: String?
    public let hasSecretKey: Bool?
    public let presignExpireSeconds: Int?
    public let presignExpireMinutes: Int?
    public let localFileCount: Int64?
    public let localTotalBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case provider
        case configured
        case accountId = "account_id"
        case bucket
        case publicDomain = "public_domain"
        case endpoint
        case accessKeyId = "access_key_id"
        case hasSecretKey = "has_secret_key"
        case presignExpireSeconds = "presign_expire_seconds"
        case presignExpireMinutes = "presign_expire_minutes"
        case localFileCount = "local_file_count"
        case localTotalBytes = "local_total_bytes"
    }

    public init(
        provider: String? = nil,
        configured: Bool = false,
        accountId: String? = nil,
        bucket: String? = nil,
        publicDomain: String? = nil,
        endpoint: String? = nil,
        accessKeyId: String? = nil,
        hasSecretKey: Bool? = nil,
        presignExpireSeconds: Int? = 1800,
        presignExpireMinutes: Int? = 30,
        localFileCount: Int64? = 0,
        localTotalBytes: Int64? = 0
    ) {
        self.provider = provider
        self.configured = configured
        self.accountId = accountId
        self.bucket = bucket
        self.publicDomain = publicDomain
        self.endpoint = endpoint
        self.accessKeyId = accessKeyId
        self.hasSecretKey = hasSecretKey
        self.presignExpireSeconds = presignExpireSeconds
        self.presignExpireMinutes = presignExpireMinutes
        self.localFileCount = localFileCount
        self.localTotalBytes = localTotalBytes
    }
}

/// 后端对象存储配置请求负载
public struct StorageConfigPayload: Codable, Sendable {
    public var accountId: String
    public var accessKeyId: String
    public var secretAccessKey: String
    public var bucketName: String
    public var endpoint: String
    public var publicDomain: String
    public var presignExpireSeconds: Int

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case accessKeyId = "access_key_id"
        case secretAccessKey = "secret_access_key"
        case bucketName = "bucket_name"
        case endpoint
        case publicDomain = "public_domain"
        case presignExpireSeconds = "presign_expire_seconds"
    }

    public init(
        accountId: String = "",
        accessKeyId: String = "",
        secretAccessKey: String = "",
        bucketName: String = "",
        endpoint: String = "",
        publicDomain: String = "",
        presignExpireSeconds: Int = 1800
    ) {
        self.accountId = accountId
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.bucketName = bucketName
        self.endpoint = endpoint
        self.publicDomain = publicDomain
        self.presignExpireSeconds = presignExpireSeconds
    }
}

/// 对象存储握手连通测试响应
public struct StorageTestResponse: Codable, Sendable {
    public let status: String?
    public let message: String?
    public let latencyMs: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case message
        case latencyMs = "latency_ms"
    }
}

/// 媒体双向增量同步响应
public struct StorageMigrateResponse: Codable, Sendable {
    public let uploadedToR2: Int?
    public let downloadedToLocal: Int?
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case uploadedToR2 = "uploaded_to_r2"
        case downloadedToLocal = "downloaded_to_local"
        case message
    }
}

