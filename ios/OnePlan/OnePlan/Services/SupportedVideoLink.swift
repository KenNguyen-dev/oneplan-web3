//
//  SupportedVideoLink.swift
//  OnePlan
//
//  Pure, extension-safe validation of supported video links (Instagram /
//  TikTok). Foundation-only (NSDataDetector + String) so the same rules compile
//  and run inside the Share Extension target as well as the app. Do NOT add
//  UIKit / UIPasteboard / AnalyticsClient references here — those belong at the
//  BoardView / extension call sites. Extracted from BoardView's former private
//  statics so paste-link and share-sheet flows validate identically.
//

import Foundation

enum SupportedVideoLink {
    /// Extracts the first supported Instagram/TikTok link from arbitrary text —
    /// either a bare URL or a block of text containing one. Returns nil when no
    /// supported link is present.
    static func extract(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.contains(where: \.isWhitespace), isSupported(trimmed) {
            return trimmed
        }

        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return nil
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        for match in detector.matches(in: trimmed, range: range) {
            guard let matchRange = Range(match.range, in: trimmed) else { continue }
            let candidate = String(trimmed[matchRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isSupported(candidate) {
                return candidate
            }
        }

        return nil
    }

    static func isSupported(_ link: String) -> Bool {
        let lower = link.lowercased()
        return lower.contains("instagram.com") || lower.contains("tiktok.com")
    }

    /// Analytics-friendly platform discriminator for a (already-validated) link.
    static func platform(of link: String) -> String {
        let lower = link.lowercased()
        if lower.contains("tiktok") { return "tiktok" }
        if lower.contains("instagram") { return "instagram" }
        return "other"
    }
}
