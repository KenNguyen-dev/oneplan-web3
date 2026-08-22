//
//  UserProfileService.swift
//  OnePlan
//

import Foundation
import OSLog
import UIKit

typealias UserProfileDto = Components.Schemas.UserProfileDto

@MainActor
@Observable
final class UserProfileService {
    /// Persisted to disk on every successful load/update so the name + avatar
    /// can be shown offline (see didSet / loadCachedProfile).
    var profile: UserProfileDto? {
        didSet { persistProfileIfPossible() }
    }
    var isLoading = false
    var isUploadingAvatar = false
    var error: String?

    private var client: Client { APIClient.shared }
    private let uploadService = StorageUploadService()
    private let cacheCoder = (encoder: JSONEncoder(), decoder: JSONDecoder())
    private static let cacheDefaultsKey = "oneplan.cachedUserProfile"
    private static let logger = Logger(
        subsystem: "ken.OnePlan",
        category: "UserProfileService"
    )

    func reset() {
        profile = nil
        error = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheDefaultsKey)
    }

    func fetchProfile(force: Bool = false) async {
        if !force { guard profile == nil else { return } }
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.getProfile(.init())
            profile = try response.ok.body.json
        } catch {
            // Offline: fall back to the cached profile so the name/avatar still
            // show; never surface an error when we're just offline.
            if isOfflineError(error) {
                if profile == nil, let cached = loadCachedProfile() {
                    profile = cached
                }
            } else {
                self.error = String(localized: "Failed to load profile")
            }
        }
    }

    // MARK: - Offline cache

    private func persistProfileIfPossible() {
        // Keep the last good profile; don't wipe the cache on a transient nil
        // (logout clears it explicitly in reset()).
        guard let profile else { return }
        guard let data = try? cacheCoder.encoder.encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheDefaultsKey)
    }

    private func loadCachedProfile() -> UserProfileDto? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheDefaultsKey) else {
            return nil
        }
        return try? cacheCoder.decoder.decode(UserProfileDto.self, from: data)
    }

    func uploadAvatar(_ image: UIImage) async {
        guard profile?.id != nil else {
            Self.logger.debug("uploadAvatar called before profile loaded")
            return
        }

        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        do {
            // We deliberately don't log the presigned URL here — it's a
            // short-lived bearer credential to S3. The objectKey is safe but
            // adds no value to the log either.
            _ = try await uploadService.uploadImage(
                image,
                target: .user_hyphen_avatar,
                entityId: profile?.id ?? 0
            )
            await fetchProfile(force: true)
        } catch {
            Self.logger.error("uploadAvatar failed")
            self.error = String(localized: "Failed to upload avatar")
        }
    }

    func updateDisplayName(_ displayName: String) async {
        let normalizedDisplayName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedDisplayName.isEmpty else {
            error = String(localized: "Display name cannot be empty")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.updateProfile(
                .init(
                    body: .json(
                        .init(displayName: normalizedDisplayName)
                    )
                )
            )
            profile = try response.ok.body.json
        } catch {
            self.error = String(localized: "Failed to update display name")
        }
    }

    /// Toggle engagement (marketing) push nudges. Pass `grantConsent: true`
    /// the first time the user opts in — the server stamps the auditable
    /// marketing-consent timestamp (App Store 4.5.4); enabling without prior
    /// consent would leave the cron's consent gate closed.
    func setEngagementPushEnabled(_ enabled: Bool, grantConsent: Bool) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.updateProfile(
                .init(
                    body: .json(
                        .init(
                            engagementPushEnabled: enabled,
                            engagementConsent: grantConsent ? true : nil
                        )
                    )
                )
            )
            profile = try response.ok.body.json
        } catch {
            self.error = String(localized: "Failed to update notification settings")
        }
    }

    /// Sync the user's chosen display language to the server so push
    /// notifications (which are localized server-side from `User.locale`) match
    /// the in-app language. The push-token registration only sends the locale
    /// when the APNs token changes, so an in-app language switch would otherwise
    /// never reach the server.
    func updateLocale(_ locale: Components.Schemas.EngagementLocale) async {
        do {
            let response = try await client.updateProfile(
                .init(
                    body: .json(
                        .init(locale: .init(value1: locale))
                    )
                )
            )
            profile = try response.ok.body.json
        } catch {
            // Best-effort: a failed sync just means pushes stay in the previous
            // language until the next successful profile update. Don't surface.
            Self.logger.error("updateLocale failed")
        }
    }

    func updatePreferredCurrency(_ currency: Components.Schemas.Currency) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.updateProfile(
                .init(
                    body: .json(
                        .init(preferredCurrency: .init(value1: currency))
                    )
                )
            )
            profile = try response.ok.body.json
        } catch {
            self.error = String(localized: "Failed to update currency")
        }
    }
}
