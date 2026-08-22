//
//  DeepLinkBuilder.swift
//  OnePlan
//

import Foundation

enum DeepLinkBuilder {
    static let friendPath = "friend"
    static let joinPath = "join"
    static let listingPath = "listing"
    static let customScheme = "oneplan"

    // Both the api.* (v1) and op.* (v2 short-link) domains are claimed by the
    // app via the Associated Domains entitlement. New shares are minted at
    // op.* (cleaner in social previews); old api.* URLs in flight stay
    // functional because the entitlement keeps both.
    static let universalLinkHosts: Set<String> = [
        "api.oneplan.space",
        "dev-api.oneplan.space",
        "op.oneplan.space",
        "dev-op.oneplan.space",
    ]

    private static var universalBaseURL: URL {
        let fallback = URL(string: "https://op.oneplan.space")!
        switch APIEnvironment.current {
        case .prod:
            return URL(string: "https://op.oneplan.space") ?? fallback
        case .dev:
            return URL(string: "https://dev-op.oneplan.space") ?? fallback
        case .local:
            // Universal Links can't match localhost; debug builds still need a
            // shareable preview URL, so fall through to dev.
            return URL(string: "https://dev-op.oneplan.space") ?? fallback
        }
    }

    static func friendURL(code: String) -> URL {
        universalBaseURL
            .appending(path: friendPath)
            .appending(path: code)
    }

    static func tripURL(code: String) -> URL {
        universalBaseURL
            .appending(path: joinPath)
            .appending(path: code)
    }

    static func listingURL(id: Int) -> URL {
        universalBaseURL
            .appending(path: listingPath)
            .appending(path: String(id))
    }

    static func customSchemeJoin(code: String) -> URL? {
        guard let escaped = code.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) else { return nil }
        return URL(string: "\(customScheme)://\(joinPath)/\(escaped)")
    }

    static func customSchemeFriend(code: String) -> URL? {
        guard let escaped = code.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) else { return nil }
        return URL(string: "\(customScheme)://\(friendPath)/\(escaped)")
    }
}
