//
//  MarketplaceAcquisitionService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

@MainActor
@Observable
final class MarketplaceAcquisitionService {
    var isApplying = false
    var applySuccess = false
    var hasApplied = false
    var acquisitionId: Int?
    var error: String?
    var isApplyingToTrip = false
    var applyToTripSuccess = false
    var applyToTripError: String?
    var isCreatingTrip = false
    var createTripSuccess = false
    var createdTripId: Int?
    var createTripError: String?

    private var client: Client { APIClient.shared }

    func checkAppliedStatus(listingId: Int) async {
        do {
            let response = try await client.getAppliedStatus(
                .init(path: .init(id: listingId))
            )
            let status = try response.ok.body.json
            hasApplied = status.applied
            acquisitionId = status.acquisitionId.map { Int($0) } ?? nil
        } catch {
            print("MarketplaceAcquisitionService.checkAppliedStatus error: \(error)")
        }
    }

    func applyForListing(listingId: Int) async {
        guard !isApplying else { return }

        isApplying = true
        defer { isApplying = false }

        do {
            let response = try await client.applyForListing(
                .init(path: .init(id: listingId))
            )
            let dto = try response.created.body.json
            applySuccess = true
            hasApplied = true
            acquisitionId = Int(dto.id)
            self.error = nil
            NotificationCenter.default.post(
                name: .marketplacePlanAcquired,
                object: nil
            )
        } catch {
            print("MarketplaceAcquisitionService.applyForListing error: \(error)")
            self.error = String(localized: "Failed to acquire this plan")
        }
    }

    func applyMarketplaceToTrip(tripId: Int, listingId: Int) async {
        guard !isApplyingToTrip else { return }

        isApplyingToTrip = true
        defer { isApplyingToTrip = false }
        applyToTripSuccess = false
        applyToTripError = nil

        // Resolve the acquisition ID for this listing (cached if available).
        var resolvedAcquisitionId = acquisitionId
        if resolvedAcquisitionId == nil {
            do {
                let response = try await client.getAppliedStatus(
                    .init(path: .init(id: listingId))
                )
                let status = try response.ok.body.json
                resolvedAcquisitionId = status.acquisitionId.map { Int($0) } ?? nil
                acquisitionId = resolvedAcquisitionId
            } catch {
                print("MarketplaceAcquisitionService.applyMarketplaceToTrip lookup error: \(error)")
                applyToTripError = String(localized: "Failed to apply plan to trip")
                return
            }
        }
        guard let acquisitionId = resolvedAcquisitionId else {
            applyToTripError = String(localized: "You have not acquired this plan")
            return
        }

        await performApplyAcquisition(tripId: tripId, acquisitionId: acquisitionId)
    }

    func applyAcquisitionToTrip(tripId: Int, acquisitionId: Int) async {
        guard !isApplyingToTrip else { return }

        isApplyingToTrip = true
        defer { isApplyingToTrip = false }
        applyToTripSuccess = false
        applyToTripError = nil

        await performApplyAcquisition(tripId: tripId, acquisitionId: acquisitionId)
    }

    /// Performs the apply-acquisition API call. Does NOT touch `isApplyingToTrip`
    /// so it can be called from `applyMarketplaceToTrip` (which already holds the
    /// flag) without the inner re-entrant guard swallowing the call.
    private func performApplyAcquisition(tripId: Int, acquisitionId: Int) async {
        do {
            let response = try await client.applyAcquisitionToTrip(
                .init(path: .init(tripId: tripId, acquisitionId: acquisitionId))
            )
            _ = try response.created.body.json
            applyToTripSuccess = true
            applyToTripError = nil

            NotificationCenter.default.post(
                name: .marketplacePlanApplied,
                object: tripId
            )
        } catch {
            print("MarketplaceAcquisitionService.applyAcquisitionToTrip error: \(error)")
            applyToTripError = String(localized: "Failed to apply plan to trip")
        }
    }

    func createTripFromListing(listingId: Int) async {
        guard !isCreatingTrip else { return }
        isCreatingTrip = true
        defer { isCreatingTrip = false }

        do {
            let response = try await client.createTripFromListing(
                .init(path: .init(id: listingId))
            )
            let trip = try response.created.body.json
            createdTripId = Int(trip.id)
            createTripSuccess = true
            createTripError = nil
        } catch {
            print("MarketplaceAcquisitionService.createTripFromListing error: \(error)")
            createTripError = String(localized: "Failed to create trip from this plan")
        }
    }
}
