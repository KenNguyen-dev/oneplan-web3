//
//  PassportMRZLines.swift
//  OnePlan
//

import SwiftUI

struct PassportMRZLines: View {
    let displayName: String
    let memberSince: String?
    var foregroundColor: Color = Color.white.opacity(0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.lineOne(displayName: displayName, memberSince: memberSince))
            Text(Self.lineTwo(memberSince: memberSince))
        }
        .font(.system(size: 10, weight: .regular, design: .rounded))
        .tracking(-0.3)
        .foregroundStyle(foregroundColor)
        .lineLimit(1)
    }

    static func lineOne(displayName: String, memberSince: String?) -> String {
        let raw = "<<ALLTIME<<\(token(displayName))<<MEMBERSINCE\(dateToken(memberSince))<<ONEPLAN TRAVEL<<PASSPORT"
        return pad(raw, to: 64)
    }

    static func lineTwo(memberSince: String?) -> String {
        let issuedPrefix = "ISSUED\(dateToken(memberSince))SGN"
        let suffix = "ONEPLAN TRAVEL"
        let targetLength = 54
        let fillerCount = max(1, targetLength - issuedPrefix.count - suffix.count)
        let raw = issuedPrefix + String(repeating: "<", count: fillerCount) + suffix
        return String(raw.prefix(targetLength))
    }

    private static func token(_ value: String) -> String {
        let asciiUppercased = value
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
        let replaced = asciiUppercased.replacingOccurrences(
            of: "[^A-Z0-9]+",
            with: "<",
            options: .regularExpression
        )
        let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "<"))
        return trimmed.isEmpty ? "MEMBER" : trimmed
    }

    private static func dateToken(_ rawDate: String?) -> String {
        guard let rawDate, let date = isoDate(from: rawDate) else {
            return "01JAN25"
        }
        return mrzDateFormatter.string(from: date).uppercased()
    }

    private static func pad(_ value: String, to targetLength: Int) -> String {
        if value.count >= targetLength {
            return String(value.prefix(targetLength))
        }
        return value + String(repeating: "<", count: targetLength - value.count)
    }

    private static func isoDate(from value: String) -> Date? {
        isoFormatterWithFractionalSeconds.date(from: value)
            ?? isoFormatter.date(from: value)
            ?? isoDateOnlyFormatter.date(from: value)
    }

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let mrzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "ddMMMyy"
        return formatter
    }()
}
