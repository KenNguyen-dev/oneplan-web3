//
//  VersionCheckManager.swift
//  OnePlan
//
//  Checks the App Store for a newer version via the public iTunes Lookup API.
//  Returns a result ONLY when the installed CFBundleShortVersionString is behind
//  the live App Store version — that non-nil result is the "must update" signal
//  (OnePlan forces every update; there is no optional path). Any network/parse
//  failure returns nil, so the gate fails open (no block when offline or when the
//  bundle id isn't on the App Store, e.g. dev/local builds).
//

import SwiftUI

@MainActor
class VersionCheckManager {
    static let shared = VersionCheckManager()

    func checkIfAppUpdateAvailable() async -> ReturnResult? {
        do {
            /// NOTE: You can also use App ID directly, e.g.
            /// "https://itunes.apple.com/lookup?id=\(appID)"
            guard let bundleID,
                let lookupURL = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)") else {
                return nil
            }

            let data = try await URLSession.shared.data(from: lookupURL).0

            guard let rawJSON = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return nil
            }

            guard let jsonResults = rawJSON["results"] as? [Any] else {
                return nil
            }

            guard let jsonValue = jsonResults.first as? [String: Any] else {
                return nil
            }

            /// Only these three are required for the gate. `releaseNotes` and
            /// `artworkUrl512` are intentionally optional — iTunes sometimes omits
            /// `releaseNotes`, and a single mandatory guard would silently fail the
            /// gate. The OnePlan view uses a bundled illustration, not `appLogo`.
            guard let availableVersion = jsonValue["version"] as? String,
                  let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  let appURL = (jsonValue["trackViewUrl"] as? String)?.components(separatedBy: "?").first else {
                return nil
            }

            let appLogo = jsonValue["artworkUrl512"] as? String ?? ""
            let releaseNotes = jsonValue["releaseNotes"] as? String ?? ""

            if currentVersion.compare(availableVersion, options: .numeric) == .orderedAscending {
                return .init(
                    currentVersion: currentVersion,
                    availableVersion: availableVersion,
                    releaseNotes: releaseNotes,
                    appLogo: appLogo,
                    appURL: appURL
                )
            }

            return nil
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }

    var bundleID: String? {
        return Bundle.main.bundleIdentifier
        /// FOR TESTING: return a live App Store app's bundle id to force the gate
        /// (dev/local bundle ids aren't on the App Store, so the lookup is empty).
        //return "Use any of the live app bundle IDs"
    }

    struct ReturnResult: Identifiable {
        private(set) var id: String = UUID().uuidString
        var currentVersion: String
        var availableVersion: String
        var releaseNotes: String
        var appLogo: String
        var appURL: String
    }
}
