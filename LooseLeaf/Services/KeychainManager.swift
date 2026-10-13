import Foundation
import Security

/// 系统钥匙串安全凭据管理中枢 (Keychain Services)
/// 严格遵循 docs/macos.md §5.1：device_token 与 device_id 绝不明文保存在 UserDefaults 或 plist 文件中
public final class KeychainManager: Sendable {
    public static let serviceName = "com.looseleaf.archive.desktop"
    public static let tokenAccount = "DeviceToken"
    public static let deviceIdAccount = "DeviceID"
    public static let deviceNameAccount = "DeviceName"

    /// 内存兜底（仅用于无签名 CI 单元测试环境）
    private static let lock = NSLock()
    private nonisolated(unsafe) static var memoryFallback: [String: String] = [:]

    // MARK: - Device Token

    @discardableResult
    public static func saveToken(_ token: String) -> Bool {
        saveString(token, account: tokenAccount)
    }

    public static func getToken() -> String? {
        getString(account: tokenAccount)
    }

    @discardableResult
    public static func deleteToken() -> Bool {
        deleteItem(account: tokenAccount)
    }

    // MARK: - Device ID & Name

    @discardableResult
    public static func saveDeviceIdentity(deviceId: String, deviceName: String) -> Bool {
        let ok1 = saveString(deviceId, account: deviceIdAccount)
        let ok2 = saveString(deviceName, account: deviceNameAccount)
        return ok1 && ok2
    }

    public static func getDeviceId() -> String? {
        getString(account: deviceIdAccount)
    }

    public static func getDeviceName() -> String? {
        getString(account: deviceNameAccount)
    }

    public static func clearAllCredentials() {
        _ = deleteItem(account: tokenAccount)
        _ = deleteItem(account: deviceIdAccount)
        _ = deleteItem(account: deviceNameAccount)
    }

    // MARK: - Keychain 底层读写

    private static func saveString(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }
        if status == errSecMissingEntitlement {
            // 无签名 CI / 单元测试环境无钥匙串权限：降级为进程内内存兜底（重启即失效，仅测试场景）
            lock.lock()
            memoryFallback[account] = value
            lock.unlock()
            return true
        }
        // 其他钥匙串错误不写内存兜底，避免「看似保存成功、重启即丢失」的假象
        return false
    }

    private static func getString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
            return str
        }

        lock.lock()
        let fallback = memoryFallback[account]
        lock.unlock()
        return fallback
    }

    private static func deleteItem(account: String) -> Bool {
        lock.lock()
        memoryFallback.removeValue(forKey: account)
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
