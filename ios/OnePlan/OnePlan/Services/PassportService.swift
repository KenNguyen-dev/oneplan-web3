//
//  PassportService.swift
//  OnePlan
//

import Foundation

typealias PassportSummaryDto = Components.Schemas.PassportSummaryDto

@MainActor
@Observable
final class PassportService {
    /// All-time summary (compact card in ProfileView + chip year range).
    var summary: PassportSummaryDto?
    /// Summary filtered to `selectedYear`; nil while "All time" is selected.
    var filteredSummary: PassportSummaryDto?
    /// nil == "All time".
    var selectedYear: Int?
    var isLoading = false
    var error: String?

    /// Falls back to the last shown data while a year fetch is in flight (or
    /// failed) — nil would surface the preview placeholder content.
    var displayedSummary: PassportSummaryDto? {
        guard selectedYear != nil else { return summary }
        return filteredSummary ?? summary
    }

    private var client: Client { APIClient.shared }

    func reset() {
        summary = nil
        filteredSummary = nil
        selectedYear = nil
        error = nil
    }

    func fetchSummary(force: Bool = false) async {
        if !force, summary != nil { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.getPassportSummary(.init())
            summary = try response.ok.body.json
        } catch {
            self.error = String(localized: "Failed to load passport summary")
        }
    }

    func selectYear(_ year: Int?) async {
        selectedYear = year
        guard let year else {
            filteredSummary = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.getPassportSummary(
                .init(query: .init(year: year))
            )
            let result = try response.ok.body.json
            // Ignore out-of-order responses from rapid chip taps.
            guard selectedYear == year else { return }
            filteredSummary = result
        } catch {
            self.error = String(localized: "Failed to load passport summary")
        }
    }
}
