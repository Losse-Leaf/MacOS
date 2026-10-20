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
        let payload = Payload()
        cachedPayload = payload
        lock.unlock()
        writePayload(payload)
    }

    // MARK: - 底层读写

    /// 读取凭据。
    /// 关键：**持锁完成磁盘加载**。原先的「解锁 → 读盘 → 再加锁写缓存」存在丢失更新竞态：
    /// 线程 A 读到旧磁盘内容后，线程 B 写入了新令牌，随后 A 用旧内容覆盖了缓存，
    /// 导致刚保存的令牌凭空消失、用户被迫重新配对。
    private static func read<T>(_ transform: (Payload?) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPayload {
            return transform(cachedPayload)
        }
        let payload = loadFromDisk()
        cachedPayload = payload
        return transform(payload)
    }

    /// 修改并落盘。锁内完成「读-改-写」，保证并发写不会互相覆盖。
    private static func mutate(_ change: (inout Payload) -> Void) -> Bool {
        lock.lock()
        var payload = cachedPayload ?? loadFromDisk() ?? Payload()
        change(&payload)
        cachedPayload = payload
        let written = writePayload(payload)
        lock.unlock()
        return written
    }

    private static var storageDirectory: URL {
        if let overrideDirectory {
            return overrideDirectory
        }
        return SyncManager.sharedStorageDirectory
    }

    private static var fileURL: URL {
        storageDirectory.appendingPathComponent("credentials.json")
    }

    private static func loadFromDisk() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// 原子落盘凭据。
    /// 关键：**先设权限再原子替换**。原先的 `write(.atomic)` 会先写临时文件再 rename，
    /// rename 后的文件继承 umask（通常 0644），之后才收紧到 0600 —— 中间存在窗口期，
    /// 且若收紧失败，文件将永久保持 0644 而函数却报告失败。
    @discardableResult
    private static func writePayload(_ payload: Payload) -> Bool {
        let dir = storageDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        } catch {
            // 目录权限收紧失败不阻断写入（写入时会再次尝试设置文件权限）
        }
        guard let data = try? JSONEncoder().encode(payload) else { return false }

        let url = fileURL
        let tmpURL = dir.appendingPathComponent("credentials.json.tmp")
        do {
            try data.write(to: tmpURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: url)
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            return false
        }
    }
}
