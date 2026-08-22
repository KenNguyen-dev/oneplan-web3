//
//  MarketplaceListingDetailService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

@MainActor
@Observable
final class MarketplaceListingDetailService {
    var isLoading = false
    var listing: Components.Schemas.MarketplaceListingDto?
    var error: String?

    private var client: Client { APIClient.shared }

    func fetchListing(id: Int) async {
        if isLoading { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.getListing(
                .init(path: .init(id: String(id)))
            )
            listing = try response.ok.body.json
            error = nil
        } catch {
            print("MarketplaceListingDetailService.fetchListing error: \(error)")
            self.error = String(localized: "Failed to load marketplace listing detail")
        }
    }
}
