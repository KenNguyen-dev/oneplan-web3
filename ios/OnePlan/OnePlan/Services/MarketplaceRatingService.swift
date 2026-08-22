//
//  MarketplaceRatingService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

struct ListingRatingUpdate {
    let listingId: Int
    let average: Double?
    let count: Int
    let userRating: Int
}

@MainActor
@Observable
final class MarketplaceRatingService {
    var isSubmitting: Bool = false
    var lastError: String?

    private var client: Client { APIClient.shared }

    struct RatingResult {
        let userRating: Int
        let average: Double?
        let count: Int
    }

    func submitRating(listingId: Int, rating: Int) async throws -> RatingResult {
        isSubmitting = true
        lastError = nil
        defer { isSubmitting = false }

        do {
            let response = try await client.rateListing(
                .init(
                    path: .init(id: listingId),
                    body: .json(.init(rating: Double(rating)))
                )
            )

            let body: Components.Schemas.MarketplaceRatingResponseDto
            switch response {
            case .ok(let ok):
                body = try ok.body.json
            case .created(let created):
                body = try created.body.json
            case .forbidden:
                let message = String(localized: "You can only rate plans you've completed.")
                self.lastError = message
                throw MarketplaceRatingError.forbidden(message)
            case .notFound:
                let message = String(localized: "Listing not found.")
                self.lastError = message
                throw MarketplaceRatingError.notFound(message)
            case .undocumented(statusCode: let code, _):
                let message = String(localized: "Unexpected response (status \(code)).")
                self.lastError = message
                throw MarketplaceRatingError.unexpected(message)
            }

            let avg: Double? = body.averageRating.flatMap { Double($0) }
            let count = Int(body.ratingCount)
            let userRating = Int(body.userRating)
            let result = RatingResult(userRating: userRating, average: avg, count: count)

            NotificationCenter.default.post(
                name: .marketplaceListingRated,
                object: ListingRatingUpdate(
                    listingId: listingId,
                    average: avg,
                    count: count,
                    userRating: userRating
                )
            )
            return result
        } catch let error as MarketplaceRatingError {
            throw error
        } catch {
            print("MarketplaceRatingService.submitRating error: \(error)")
            self.lastError = String(localized: "Failed to submit rating")
            throw error
        }
    }
}

enum MarketplaceRatingError: LocalizedError {
    case forbidden(String)
    case notFound(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .forbidden(let message), .notFound(let message), .unexpected(let message):
            return message
        }
    }
}
