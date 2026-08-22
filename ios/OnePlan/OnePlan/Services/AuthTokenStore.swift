//
//  AuthTokenStore.swift
//  OnePlan
//

import Foundation
import Security

final class AuthTokenStore {
    static let shared = AuthTokenStore()

    private let accessTokenKey = "com.oneplan.accessToken"
    private let refreshTokenKey = "com.oneplan.refreshToken"
    private let appleUserIDKey = "com.oneplan.appleUserID"

    private init() {}

    var accessToken: String? {
        get { read(key: accessTokenKey) }
        set {
            if let newValue {
                save(key: accessTokenKey, value: newValue)
            } else {
                delete(key: accessTokenKey)
            }
        }
    }

    var refreshToken: String? {
        get { read(key: refreshTokenKey) }
        set {
            if let newValue {
                save(key: refreshTokenKey, value: newValue)
            } else {
                delete(key: refreshTokenKey)
            }
        }
    }

    var appleUserID: String? {
        get { read(key: appleUserIDKey) }
        set {
            if let newValue {
                save(key: appleUserIDKey, value: newValue)
            } else {
                delete(key: appleUserIDKey)
            }
        }
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
        appleUserID = nil
    }

    // MARK: - Keychain helpers

    // `AfterFirstUnlockThisDeviceOnly` keeps tokens available for background
    // network work after the first device unlock and prevents them from
    // being included in iCloud Keychain or encrypted iTunes backups (i.e.,
    // they cannot be restored to a different device).
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private func save(key: String, value: String) {
        let data = Data(value.utf8)
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.accessibility,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
