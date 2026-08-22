//
//  RecentLocationService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

typealias RecentLocationDto = Components.Schemas.RecentLocationDto

@MainActor
@Observable
final class RecentLocationService {
    var recentLocations: [RecentLocationDto] = []
    var isLoading = false
    var error: String?

    private var client: Client { APIClient.shared }

    func fetchRecent(limit: Int = 10) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.listRecentLocations(.init(
                query: .init(limit: limit)
            ))
            recentLocations = try response.ok.body.json
        } catch {
            self.error = String(localized: "Failed to load recent locations")
        }
    }

    func saveRecent(name: String, address: String?, latitude: Double?, longitude: Double?, pointOfInterestCategory: String?) async {
        do {
            let response = try await client.saveRecentLocation(.init(
                body: .json(.init(
                    name: name,
                    address: address,
                    latitude: latitude,
                    longitude: longitude,
                    pointOfInterestCategory: pointOfInterestCategory
                ))
            ))
            let saved = try response.created.body.json
            // Move to front of list (match on name+address like server's unique constraint)
            recentLocations.removeAll { $0.name == saved.name && $0.address == saved.address }
            recentLocations.insert(saved, at: 0)
        } catch {
            // Non-critical: don't surface error to user
            print("[RecentLocation] save failed: \(error)")
        }
    }
}
