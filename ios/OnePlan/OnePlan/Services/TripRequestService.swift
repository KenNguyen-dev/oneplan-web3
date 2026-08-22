//
//  TripRequestService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

enum TripRequestError: Error {
    /// User already has an OPEN request for this destination (HTTP 409).
    case duplicateOpenRequest
    case requestFailed
}

@MainActor
@Observable
final class TripRequestService {
    var isSubmitting = false

    private var client: Client { APIClient.shared }

    func submitRequest(
        destination: SelectedMarketDestination,
        tag: Components.Schemas.ListingTag,
        budget: Double?,
        currency: Components.Schemas.Currency
    ) async throws {
        isSubmitting = true
        defer { isSubmitting = false }

        let body = Components.Schemas.CreateTripRequestDto(
            cityId: destination.cityId,
            stateId: destination.stateId,
            countryId: destination.countryId,
            tag: .init(value1: tag),
            budget: budget,
            currency: .init(value1: currency)
        )

        let response = try await client.createTripRequest(.init(body: .json(body)))
        switch response {
        case .created:
            return
        case .conflict:
            throw TripRequestError.duplicateOpenRequest
        default:
            throw TripRequestError.requestFailed
        }
    }
}
