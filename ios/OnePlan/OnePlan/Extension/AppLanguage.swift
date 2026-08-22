//
//  AppLanguage.swift
//  OnePlan
//
//  User-selectable display languages, backed by the standard `AppleLanguages`
//  UserDefaults override. iOS reads that key at launch, so a change only takes
//  effect after the app is relaunched.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case vietnamese = "vi"

    var id: String { rawValue }

    /// Autonym — each language is shown in its own name and is never localized.
    var displayName: String {
        switch self {
        case .english: "English"
        case .vietnamese: "Tiếng Việt"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .vietnamese: "🇻🇳"
        }
    }

    /// The server-side engagement/push locale this language maps to. Only
    /// Vietnamese has a dedicated locale; everything else falls back to English.
    var engagementLocale: Components.Schemas.EngagementLocale {
        self == .vietnamese ? .VN : .EN
    }

    private static let appleLanguagesKey = "AppleLanguages"

    /// The language the app currently presents. Prefers an explicit override
    /// (so a freshly-picked language shows immediately, even before the restart
    /// that actually applies it), then falls back to the resolved bundle
    /// language, then English.
    static var current: AppLanguage {
        if let override = UserDefaults.standard.array(forKey: appleLanguagesKey) as? [String] {
            for code in override {
                if let match = AppLanguage(rawValue: String(code.prefix(2))) {
                    return match
                }
            }
        }
        for code in Bundle.main.preferredLocalizations {
            if let match = AppLanguage(rawValue: String(code.prefix(2))) {
                return match
            }
        }
        return .english
    }

    /// Persists the override. Takes effect on the next cold launch.
    func apply() {
        UserDefaults.standard.set([rawValue], forKey: Self.appleLanguagesKey)
    }
}
