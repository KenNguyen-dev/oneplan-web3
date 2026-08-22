//
//  PassportView.swift
//  OnePlan
//
//  Created by ken on 25/3/26.
//

import MessageUI
import SwiftUI

struct PassportView: View {
    @Environment(UserProfileService.self) private var userProfileService
    @Environment(PassportService.self) private var passportService

    @State private var photoService = PhotoDownloadService()
    @State private var messageImage: UIImage?
    @State private var shareSheetImage: UIImage?
    @State private var saveResultMessage: String?

    var body: some View {
        let summary = passportService.displayedSummary
        let fallbackName = userProfileService.profile?.displayName ?? "Dannyxs Dinh"

        ScrollView(showsIndicators: false) {
            PassportCard(
                summary: summary,
                fallbackDisplayName: fallbackName,
                selectedYear: passportService.selectedYear,
                availableYears: availableYears,
                onSelectYear: { year in
                    Task { await passportService.selectYear(year) }
                },
                onShare: { action in
                    handleShare(action, summary: summary, fallbackName: fallbackName)
                }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            PassportVisitInsightsSection(summary: summary)
        }
        .frame(maxWidth: .infinity)
        .background(Constants.Background)
        .task {
            await userProfileService.fetchProfile()
            await passportService.fetchSummary()
        }
        .sheet(
            isPresented: Binding(
                get: { messageImage != nil },
                set: { if !$0 { messageImage = nil } }
            )
        ) {
            if let messageImage {
                MessageComposeView(image: messageImage, filename: "passport.png")
                    .ignoresSafeArea()
            }
        }
        .sheet(
            isPresented: Binding(
                get: { shareSheetImage != nil },
                set: { if !$0 { shareSheetImage = nil } }
            )
        ) {
            if let shareSheetImage {
                ActivityShareSheet(items: [shareSheetImage])
                    .presentationDetents([.medium, .large])
            }
        }
        .alert(
            saveResultMessage ?? "",
            isPresented: Binding(
                get: { saveResultMessage != nil },
                set: { if !$0 { saveResultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    /// memberSince year → current year, descending. Clamped so a future
    /// memberSince can't produce an empty/inverted range.
    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        var startYear = currentYear
        if let memberSince = passportService.summary?.memberSince,
           let date = Self.isoDate(from: memberSince) {
            startYear = min(Calendar.current.component(.year, from: date), currentYear)
        }
        return Array((startYear...currentYear).reversed())
    }

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    private static func isoDate(from value: String) -> Date? {
        isoFormatterWithFractionalSeconds.date(from: value)
            ?? isoFormatter.date(from: value)
    }

    private func handleShare(_ action: PassportShareAction, summary: PassportSummaryDto?, fallbackName: String) {
        guard let image = PassportShareService.renderCardImage(
            summary: summary,
            fallbackDisplayName: fallbackName
        ) else {
            saveResultMessage = String(localized: "Could not render the passport image")
            return
        }

        switch action {
        case .instagramStories:
            if !PassportShareService.shareToInstagramStories(image) {
                shareSheetImage = image
            }
        case .message:
            if MessageComposeView.canSendImage {
                messageImage = image
            } else {
                shareSheetImage = image
            }
        case .photos:
            Task {
                switch await photoService.saveImage(image) {
                case .success:
                    saveResultMessage = String(localized: "Saved to Photos")
                case .permissionDenied:
                    saveResultMessage = String(localized: "Allow photo library access in Settings to save your passport")
                case .failure(let message):
                    saveResultMessage = message
                }
            }
        }
    }
}

struct PassportVisitInsightsSection: View {
    let summary: PassportSummaryDto?

    var body: some View {
        let cityRows = resolvedCityRows
        let countryRows = resolvedCountryRows

        VStack(alignment: .leading, spacing: 30) {
            PassportDistributionSection(
                title: "Top Cities",
                totalValue: totalCitiesValue,
                totalSuffix: "cities",
                rows: cityRows,
                maxCount: max(cityRows.map(\.count).max() ?? 1, 1)
            )

            PassportDistributionSection(
                title: "Countries & Territories",
                totalValue: totalCountriesValue,
                totalSuffix: "total",
                rows: countryRows,
                maxCount: max(countryRows.map(\.count).max() ?? 1, 1)
            )
        }
    }

    private var totalCitiesValue: String {
        guard let summary else { return "04" }
        return String(format: "%02d", max(Int(summary.citiesCount), 0))
    }

    private var totalCountriesValue: String {
        guard let summary else { return "03" }
        return String(format: "%02d", max(Int(summary.countriesCount), 0))
    }

    private var resolvedCityRows: [PassportDistributionRow] {
        guard let summary else {
            return [
                PassportDistributionRow(label: "Da Lat", count: 10),
                PassportDistributionRow(label: "Vung Tau", count: 5),
                PassportDistributionRow(label: "Ha Noi", count: 1),
                PassportDistributionRow(label: "Bankok", count: 1),
            ]
        }

        return summary.topCities.map {
            PassportDistributionRow(label: $0.name, count: Int($0.count))
        }
    }

    private var resolvedCountryRows: [PassportDistributionRow] {
        guard let summary else {
            return [
                PassportDistributionRow(label: "Viet Nam", count: 4),
                PassportDistributionRow(label: "Thailand", count: 2),
                PassportDistributionRow(label: "UAE", count: 1),
            ]
        }

        return summary.topCountries.map {
            PassportDistributionRow(label: $0.name, count: Int($0.count))
        }
    }
}

struct PassportDistributionSection: View {
    let title: LocalizedStringKey
    let totalValue: String
    let totalSuffix: LocalizedStringKey
    let rows: [PassportDistributionRow]
    let maxCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .overlay(Constants.Neutral100)

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentB)

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(totalValue)
                            .font(Font.beVietnamPro(24, weight: .medium))
                            .foregroundStyle(Constants.ContentB)

                        Text(totalSuffix)
                            .font(Font.custom("Be Vietnam Pro", size: 16))
                            .foregroundStyle(Constants.ContentL)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        PassportDistributionRowView(row: row, maxCount: maxCount)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct PassportDistributionRowView: View {
    let row: PassportDistributionRow
    let maxCount: Int

    var body: some View {
        HStack(spacing: 11) {
            Text(row.label)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentB)
                .tracking(-0.7)
                .frame(width: 90, alignment: .leading)

            GeometryReader { proxy in
                let safeMax = max(maxCount, 1)
                let ratio = CGFloat(row.count) / CGFloat(safeMax)
                let barWidth = max(12.624, proxy.size.width * ratio)

                Capsule()
                    .fill(Constants.BlueBase)
                    .frame(width: barWidth, height: 10, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 10)

            Text("\(row.count)")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.7)
        }
    }
}

struct PassportDistributionRow: Identifiable {
    let label: String
    let count: Int

    var id: String { label }
}

#Preview {
    PassportView()
        .environment(UserProfileService())
        .environment(PassportService())
}
