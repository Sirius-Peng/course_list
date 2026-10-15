import Foundation
import Security
import ScheduleCore

struct SecureSubscriptionStore {
    private let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.courselist.ics-subscription", kSecAttrAccount as String: "active-feed",
        kSecAttrSynchronizable as String: false]
    func load() throws -> ICSSubscription? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ScheduleError.invalid("订阅配置暂不可读取，请解锁手机后重试") }
        do {
            let record = try JSONDecoder().decode(ICSSubscription.self, from: data)
            _ = try ICSFeedURL.normalize(record.url.absoluteString); return record
        } catch { throw ScheduleError.invalid("订阅配置读取失败，请停止后重新订阅") }
    }
    func save(_ subscription: ICSSubscription?) throws {
        guard let subscription else {
            let status = SecItemDelete(query as CFDictionary)
            guard [errSecSuccess, errSecItemNotFound].contains(status) else { throw ScheduleError.invalid("订阅配置保存失败，请解锁手机后重试") }
            return
        }
        let data = try JSONEncoder().encode(subscription)
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; values.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ScheduleError.invalid("订阅配置保存失败，请解锁手机后重试") }
        } else if status != errSecSuccess { throw ScheduleError.invalid("订阅配置保存失败，请解锁手机后重试") }
    }
}
