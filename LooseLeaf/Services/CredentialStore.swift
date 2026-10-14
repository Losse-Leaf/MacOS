import Foundation

/// 本机凭据保险箱 (Credential Vault)
/// 设备令牌存于用户目录下的受保护档案（POSIX 0600，仅当前 macOS 用户可读写）。
///
/// 为什么不用 Keychain：免签构建的 ad-hoc 签名随每次构建变化，而登录钥匙串条目的
/// ACL 绑定创建时的二进制哈希——每次重新构建/分发后启动都会反复弹出授权框
/// （「始终允许」只对当次二进制生效），对免签分发场景完全不可用。
/// 待未来以 Developer ID 公证分发（签名身份稳定）时再评估切回 Keychain。
public enum CredentialStore {
    /// 历史标识：旧版经 Keychain 写入的条目使用该 service 名（可在「钥匙串访问」中按此检索清理）
    public static let legacyKeychainServiceName = "com.looseleaf.archive.desktop"

    private static let lock = NSLock()
    /// 测试注入点：覆盖存储目录（默认 ~/Library/Application Support/LooseLeaf/）
    nonisolated(unsafe) static var overrideDirectory: URL?

    private struct Payload: Codable {
        var deviceToken: String?
        var deviceId: String?
        var deviceName: String?

        enum CodingKeys: String, CodingKey {
            case deviceToken = "device_token"
            case deviceId = "device_id"
            case deviceName = "device_name"
        }
    }

    private static var cachedPayload: Payload?

    // MARK: - Device Token

    @discardableResult
    public static func saveToken(_ token: String) -> Bool {
        mutate { $0.deviceToken = token }
    }

    public static func getToken() -> String? {
        read { $0?.deviceToken }
    }

    @discardableResult
    public static func deleteToken() -> Bool {
        mutate { $0.deviceToken = nil }
    }

    // MARK: - Device ID & Name

    @discardableResult
    public static func saveDeviceIdentity(deviceId: String, deviceName: String) -> Bool {
        mutate {
            $0.deviceId = deviceId
            $0.deviceName = deviceName
        }
    }

    public static func getDeviceId() -> String? {
        read { $0?.deviceId }
    }

    public static func getDeviceName() -> String? {
        read { $0?.deviceName }
    }

    public static func clearAllCredentials() {
        lock.lock()
        cachedPayload = Payload()
        lock.unlock()
        writePayload(Payload())
    }

    // MARK: - 底层读写

    private static func read<T>(_ transform: (Payload?) -> T) -> T {
        lock.lock()
        if let cachedPayload {
            lock.unlock()
            return transform(cachedPayload)
        }
        lock.unlock()

        let payload = loadFromDisk()
        lock.lock()
        cachedPayload = payload
        lock.unlock()
        return transform(payload)
    }

    private static func mutate(_ change: (inout Payload) -> Void) -> Bool {
        lock.lock()
        var payload = cachedPayload ?? loadFromDisk() ?? Payload()
        change(&payload)
        cachedPayload = payload
        lock.unlock()
        return writePayload(payload)
    }

    private static var storageDirectory: URL {
        if let overrideDirectory {
            return overrideDirectory
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LooseLeaf", isDirectory: true)
    }

    private static var fileURL: URL {
        storageDirectory.appendingPathComponent("credentials.json")
    }

    private static func loadFromDisk() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    @discardableResult
    private static func writePayload(_ payload: Payload) -> Bool {
        let dir = storageDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(payload) else { return false }

        let url = fileURL
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}
