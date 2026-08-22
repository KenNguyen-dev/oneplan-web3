//
//  SharedExtractionStore.swift
//  OnePlan
//
//  App Group hand-off for the Share Extension. The extension writes the shared
//  Instagram/TikTok link here; the app reads (and clears) it. Carrying the link
//  through the App Group — rather than the deep-link URL's query string — avoids
//  URL-encoding pitfalls and survives a cold launch, and makes the read
//  single-shot (whoever calls `consume()` first wins, so the .onOpenURL path and
//  the didBecomeActive fallback can't both queue the same link).
//
//  Target membership: this file must belong to BOTH the OnePlan app target and
//  the ShareExtension target. Keep it Foundation-only so it compiles in the
//  app-extension context.
//

import Foundation

enum SharedExtractionStore {
    /// Must match the `com.apple.security.application-groups` entry in both the
    /// app and the extension entitlements.
    static let suiteName = "group.lumilabs.oneplan"

    private static let key = "pendingSharedExtractionURL"

    static func write(_ link: String) {
        UserDefaults(suiteName: suiteName)?.set(link, forKey: key)
    }

    /// Reads and clears the pending link in one shot. Returns nil when empty.
    static func consume() -> String? {
        let defaults = UserDefaults(suiteName: suiteName)
        let value = defaults?.string(forKey: key)
        defaults?.removeObject(forKey: key)
        return value
    }
}
