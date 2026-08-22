//
//  LocationPickerService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

typealias CountryDto = Components.Schemas.CountryDto
typealias StateDto = Components.Schemas.StateDto
typealias CityDto = Components.Schemas.CityDto
typealias LocationSearchResultDto = Components.Schemas.LocationSearchResultDto

@MainActor
@Observable
final class LocationPickerService {
    var locationResults: [LocationSearchResultDto] = []
    var suggestedLocationResults: [LocationSearchResultDto] = []
    var isLoadingResults = false
    var isLoadingSuggestedResults = false
    var searchError: String?
    var suggestedError: String?

    private var client: Client { APIClient.shared }
    private var searchRequestId = 0
    private static var cachedSuggestedLocationResults: [LocationSearchResultDto] = []
    private let suggestedCitySearches = [
        "Tokyo",
        "Paris",
        "New York",
        "London",
        "Singapore",
        "Bangkok",
        "Seoul",
        "Rome",
        "Ho Chi Minh",
        "Da Nang",
    ]

    // MARK: - Fetch

    func fetchLocationResults(search: String) async {
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        searchRequestId += 1
        let requestId = searchRequestId

        guard trimmedSearch.count >= 2 else {
            locationResults = []
            isLoadingResults = false
            searchError = nil
            return
        }

        isLoadingResults = true
        searchError = nil
        do {
            let response = try await client.searchLocations(
                .init(
                    query: .init(
                        search: trimmedSearch,
                        take: 50
                    )
                )
            )
            let results = try response.ok.body.json
            guard requestId == searchRequestId else { return }
            locationResults = results
        } catch {
            guard requestId == searchRequestId else { return }
            searchError = String(localized: "Failed to load locations")
        }

        if requestId == searchRequestId {
            isLoadingResults = false
        }
    }

    func fetchSuggestedLocationResults() async {
        if !Self.cachedSuggestedLocationResults.isEmpty {
            suggestedLocationResults = Self.cachedSuggestedLocationResults
            suggestedError = nil
            isLoadingSuggestedResults = false
            return
        }

        guard suggestedLocationResults.isEmpty else { return }

        isLoadingSuggestedResults = true
        suggestedError = nil

        do {
            let fetchedResults = try await withThrowingTaskGroup(
                of: (Int, LocationSearchResultDto?).self
            ) { group in
                for (index, citySearch) in suggestedCitySearches.enumerated() {
                    group.addTask {
                        let response = try await APIClient.shared.searchLocations(
                            .init(
                                query: .init(
                                    search: citySearch,
                                    take: 1
                                )
                            )
                        )
                        return (index, try response.ok.body.json.first)
                    }
                }

                var results: [(Int, LocationSearchResultDto)] = []
                for try await (index, result) in group {
                    if let result {
                        results.append((index, result))
                    }
                }

                return results.sorted { $0.0 < $1.0 }.map(\.1)
            }

            var suggestions: [LocationSearchResultDto] = []
            var seenCityIds = Set<Int>()

            for result in fetchedResults {
                guard let city = result.city?.value1 else { continue }
                guard seenCityIds.insert(city.id).inserted else { continue }
                suggestions.append(result)
            }

            Self.cachedSuggestedLocationResults = suggestions
            suggestedLocationResults = suggestions
        } catch {
            suggestedError = String(localized: "Failed to load locations")
        }

        isLoadingSuggestedResults = false
    }
}
