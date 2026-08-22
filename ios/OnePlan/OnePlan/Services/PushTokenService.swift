//
//  PushTokenService.swift
//  OnePlan
//

import Foundation
import OSLog

@MainActor
final class PushTokenService {
    static let shared = PushTokenService()

    private var currentToken: String?
    private var client: Client { APIClient.shared }
    private static let logger = Logger(
        subsystem: "ken.OnePlan",
        category: "PushTokenService"
    )

    private init() {}

    func uploadToken(_ token: String) async {
        guard token != currentToken else { return }

        do {
            _ = try await client.registerDeviceToken(.init(
                body: .json(.init(
                    token: token,
                    platform: .ios,
                    locale: .init(value1: Self.deviceLocale)
                ))
            ))
            currentToken = token
        } catch {
            // Never log the error object directly — it may embed the request
            // body and therefore the device token.
            Self.logger.error("uploadToken failed")
        }
    }

    /// The device's preferred engagement-copy language. Vietnamese device →
    /// `.VN`, everything else → `.EN`. Persisted server-side so engagement
    /// pushes are localized even for users who never open Settings.
    private static var deviceLocale: Components.Schemas.EngagementLocale {
        let code = Locale.current.language.languageCode?.identifier.lowercased()
        return code == "vi" ? .VN : .EN
    }

    func removeToken() async {
        guard let token = currentToken else { return }

        do {
            _ = try await client.unregisterDeviceToken(.init(
                body: .json(.init(token: token))
            ))
            currentToken = nil
        } catch {
            Self.logger.error("removeToken failed")
        }
    }
}
