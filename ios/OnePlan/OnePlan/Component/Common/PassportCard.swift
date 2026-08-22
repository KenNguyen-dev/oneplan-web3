//
//  PassportCard.swift
//  OnePlan
//
//  Created by ken on 25/3/26.
//

import SwiftUI

enum PassportCardVariant {
    /// Chips + strip + MRZ + stats + share row (PassportView).
    case full
    /// "Total trips" + flag badges only (ProfileView peek).
    case compact
    /// Full minus chips/share row, static strip — for ImageRenderer export.
    case render
}

enum PassportShareAction {
    case instagramStories
    case message
    case photos
}

struct PassportCard: View {
    let summary: PassportSummaryDto?
    let fallbackDisplayName: String
    var variant: PassportCardVariant = .full
    var selectedYear: Int?
    var availableYears: [Int] = []
    var onSelectYear: ((Int?) -> Void)?
    var onShare: ((PassportShareAction) -> Void)?

    private let mrzColor = Color(red: 0.63, green: 0.63, blue: 0.63)
    private let dividerColor = Color(red: 0.83, green: 0.83, blue: 0.83)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch variant {
            case .compact:
                compactBody
            case .full, .render:
                fullBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: variant == .compact ? 24 : 28, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: variant == .compact ? 23 : 27, y: -2)
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            if variant == .full, let onSelectYear {
                PassportYearChips(
                    selectedYear: selectedYear,
                    availableYears: availableYears,
                    onSelect: onSelectYear
                )
            }

            if variant == .render {
                staticMarkerStrip
            } else {
                animatedMarkerStrip
            }

            mrzBlock

            dashedDivider

            PassportStatsBlock(
                summary: summary,
                countryBadges: countryBadges
            )

            dashedDivider

            mrzBlock

            if variant == .full, let onShare {
                PassportShareRow(onShare: onShare)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, variant == .full ? 28 : 16)
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            mrzBlock

            PassportStatsBlock(
                summary: summary,
                countryBadges: countryBadges,
                topRowOnly: true,
                compact: true
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 24)
    }

    private var mrzBlock: some View {
        PassportMRZLines(
            displayName: summary?.displayName ?? fallbackDisplayName,
            memberSince: summary?.memberSince,
            foregroundColor: mrzColor
        )
    }

    private var dashedDivider: some View {
        DashedLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(dividerColor)
            .frame(height: 1)
    }

    private var countryBadges: [PassportCountryBadge] {
        let palette: [Color] = [
            .red,
            Color(red: 0.92, green: 0.75, blue: 0.17),
            .white,
            Color(red: 0.45, green: 0.74, blue: 1),
            .green,
            Color(red: 0.09, green: 0.62, blue: 0.39),
        ]

        if let summary {
            return Array(summary.topCountries.prefix(6).enumerated()).map { index, country in
                PassportCountryBadge(
                    flag: country.emoji ?? "🌐",
                    background: palette[index % palette.count]
                )
            }
        }

        return [
            PassportCountryBadge(flag: "🇻🇳", background: .red),
            PassportCountryBadge(flag: "🇪🇹", background: Color(red: 0.92, green: 0.75, blue: 0.17)),
            PassportCountryBadge(flag: "🇵🇪", background: .white),
            PassportCountryBadge(flag: "🇦🇷", background: Color(red: 0.45, green: 0.74, blue: 1)),
            PassportCountryBadge(flag: "🇧🇷", background: .green),
            PassportCountryBadge(flag: "🇳🇬", background: Color(red: 0.09, green: 0.62, blue: 0.39)),
        ]
    }

    // MARK: - Marker strip

    private let markerColors: [Color] = [
        Color(red: 0.95, green: 0.78, blue: 0.25), Color(red: 0.95, green: 0.78, blue: 0.25),
        Color(red: 0.93, green: 0.85, blue: 0.30), Color(red: 0.85, green: 0.87, blue: 0.30),
        Color(red: 0.74, green: 0.86, blue: 0.27), Color(red: 0.74, green: 0.86, blue: 0.27),
        Color(red: 0.62, green: 0.84, blue: 0.26), Color(red: 0.52, green: 0.82, blue: 0.27),
        Color(red: 0.42, green: 0.78, blue: 0.30), Color(red: 0.42, green: 0.78, blue: 0.30),
        Color(red: 0.55, green: 0.83, blue: 0.27), Color(red: 0.67, green: 0.85, blue: 0.27),
        Color(red: 0.80, green: 0.86, blue: 0.28), Color(red: 0.91, green: 0.83, blue: 0.28),
        Color(red: 0.95, green: 0.78, blue: 0.25), Color(red: 0.65, green: 0.91, blue: 0.33),
    ]

    private var animatedMarkerStrip: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let phase = (elapsed * 24).truncatingRemainder(dividingBy: markerCycleWidth)
                let xOffset = reduceMotion ? 0 : (-markerCycleWidth + phase)

                HStack(spacing: 0) {
                    markerStrip
                    markerStrip
                }
                .offset(x: xOffset)
                .frame(width: proxy.size.width, alignment: .leading)
                .clipped()
            }
        }
        .frame(height: 16)
    }

    // GeometryReader collapses under ImageRenderer — render a fixed strip.
    private var staticMarkerStrip: some View {
        markerStrip
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 16)
            .clipped()
    }

    private var markerStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(markerColors.enumerated()), id: \.offset) { _, color in
                Image(systemName: "airplane")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
            }
        }
    }

    private var markerCycleWidth: CGFloat {
        let symbolWidth: CGFloat = 13
        let spacing: CGFloat = 6
        return CGFloat(markerColors.count) * symbolWidth
            + CGFloat(max(markerColors.count - 1, 0)) * spacing
            + spacing
    }
}

// MARK: - Year chips

private struct PassportYearChips: View {
    let selectedYear: Int?
    let availableYears: [Int]
    let onSelect: (Int?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                chip(label: Text("All time"), isSelected: selectedYear == nil) {
                    onSelect(nil)
                }

                ForEach(availableYears, id: \.self) { year in
                    chip(label: Text(verbatim: String(year)), isSelected: selectedYear == year) {
                        onSelect(year)
                    }
                }
            }
        }
    }

    private func chip(label: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.system(size: 14, weight: isSelected ? .medium : .regular, design: .rounded))
                .tracking(-0.42)
                .foregroundStyle(isSelected ? .white : Color(red: 0.6, green: 0.6, blue: 0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        isSelected
                            ? Color(red: 0.224, green: 0.224, blue: 0.224)
                            : Color(red: 0.898, green: 0.898, blue: 0.898)
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stats

private struct PassportStatsBlock: View {
    let summary: PassportSummaryDto?
    let countryBadges: [PassportCountryBadge]
    var topRowOnly: Bool = false
    /// Figma compact spec scales the stat block to ~0.86×.
    var compact: Bool = false

    private let primaryText = Color(red: 0.09, green: 0.09, blue: 0.09)
    private let secondaryText = Color(red: 0.32, green: 0.32, blue: 0.32)
    private let tertiaryText = Color(red: 0.45, green: 0.45, blue: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                    Text("Total trips")
                        .font(.system(size: compact ? 13 : 15, weight: .regular, design: .rounded))
                        .foregroundStyle(secondaryText)
                        .tracking(compact ? -0.39 : -0.45)

                    Text(tripsValue)
                        .font(.system(size: compact ? 41 : 48, weight: .medium, design: .rounded))
                        .foregroundStyle(primaryText)
                        .tracking(compact ? -1.24 : -1.44)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: compact ? -5 : -6) {
                    ForEach(Array(countryBadges.enumerated()), id: \.offset) { _, badge in
                        PassportFlagBadge(
                            flag: badge.flag,
                            background: badge.background,
                            size: compact ? 19 : 22
                        )
                    }
                }
            }

            if !topRowOnly {
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Member since")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(tertiaryText)
                            .tracking(-0.39)

                        Text(memberSinceValue)
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundStyle(primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Country visited")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(tertiaryText)
                            .tracking(-0.39)

                        Text(countriesValue)
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundStyle(primaryText)
                    }
                    .frame(width: 109, alignment: .leading)
                }
            }
        }
    }

    private var tripsValue: String {
        guard let summary else { return "24" }
        return "\(max(Int(summary.tripsCount), 0))"
    }

    private var countriesValue: String {
        guard let summary else { return "03" }
        return String(format: "%02d", max(Int(summary.countriesCount), 0))
    }

    private var memberSinceValue: String {
        guard let summary else { return "12 Mar 26" }
        guard let memberSinceDate = Self.isoDate(from: summary.memberSince) else {
            return "12 Mar 26"
        }
        return Self.memberSinceFormatter.string(from: memberSinceDate)
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

    private static func isoDate(from value: String) -> Date? {
        isoFormatterWithFractionalSeconds.date(from: value)
            ?? isoFormatter.date(from: value)
    }

    private static let memberSinceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // DISPLAY: month name follows the current locale.
        formatter.setLocalizedDateFormatFromTemplate("dd MMM yy")
        return formatter
    }()
}

// MARK: - Share row

private struct PassportShareRow: View {
    let onShare: (PassportShareAction) -> Void

    var body: some View {
        HStack(spacing: 24) {
            shareButton(action: .instagramStories, label: Text("IG Stories")) {
                Image("shareInstagramIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }

            shareButton(action: .message, label: Text("Message")) {
                Image("shareMessageIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }

            shareButton(action: .photos, label: Text("Photos")) {
                Image("sharePhotosIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
        }
    }

    private func shareButton(
        action: PassportShareAction,
        label: Text,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        Button {
            onShare(action)
        } label: {
            VStack(spacing: 0) {
                Circle()
                    .fill(Constants.White)
                    .frame(width: 60, height: 60)
                    .overlay(icon())

                label
                    .font(Font.beVietnamPro(12))
                    .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared pieces

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

struct PassportCountryBadge {
    let flag: String
    let background: Color
}

private struct PassportFlagBadge: View {
    let flag: String
    let background: Color
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(background)
            .frame(width: size, height: size)
            .overlay(
                Text(flag)
                    .font(.system(size: size * 0.55))
            )
            .overlay(
                Circle()
                    .stroke(Color(red: 0.33, green: 0.33, blue: 0.33).opacity(0.4), lineWidth: 0.5)
            )
    }
}

#Preview("Full") {
    PassportCard(
        summary: nil,
        fallbackDisplayName: "Danny Dinh",
        selectedYear: nil,
        availableYears: [2026, 2025],
        onSelectYear: { _ in },
        onShare: { _ in }
    )
    .padding(.horizontal, 12)
    .background(Constants.Background)
}

#Preview("Compact") {
    PassportCard(summary: nil, fallbackDisplayName: "Danny Dinh", variant: .compact)
        .padding(.horizontal, 30)
        .background(Constants.Background)
}
