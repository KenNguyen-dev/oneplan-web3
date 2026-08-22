//
//  TripService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

typealias CreateTripDto = Components.Schemas.CreateTripDto
typealias InvitePreviewDto = Components.Schemas.InvitePreviewDto
typealias TripDto = Components.Schemas.TripDto
typealias TripSummaryDto = Components.Schemas.TripSummaryDto
typealias TripLocationDto = Components.Schemas.TripLocationDto

@MainActor
@Observable
final class TripService {
    static let nonPremiumPlanningTripLimit = 3

    var isCreating = false
    var isLoadingTrips = false
    var ongoingTrips: [TripSummaryDto] = []
    var planningTrips: [TripSummaryDto] = []
    var endedTrips: [TripSummaryDto] = []
    var error: String?

    /// True when `ongoingTrips` was served from the offline cache.
    var isServingCachedData = false

    private var client: Client { APIClient.shared }
    private let cache = OngoingTripCache.shared

    var hasReachedNonPremiumPlanningTripLimit: Bool {
        planningTrips.count >= Self.nonPremiumPlanningTripLimit
    }

    func canCreatePlanningTrip(isPro: Bool) -> Bool {
        isPro || !hasReachedNonPremiumPlanningTripLimit
    }

    func listMyTrips(force: Bool = false) async {
        // Return early if already loaded (unless forced by a notification refresh)
        if !force, (!ongoingTrips.isEmpty || !planningTrips.isEmpty || !endedTrips.isEmpty) {
            return
        }

        isLoadingTrips = true
        defer { isLoadingTrips = false }

        do {
            let response = try await client.listMyTrips(.init())
            let trips = try response.ok.body.json
            ongoingTrips = trips.filter { $0.status.value1 == .ONGOING }
            planningTrips = trips.filter { $0.status.value1 == .PLANNING }
            endedTrips = trips.filter { $0.status.value1 == .ENDED }
            isServingCachedData = false

            // Cache each ongoing trip's summary so the card renders offline, and
            // prune snapshots for trips that are no longer ONGOING (authoritative
            // status lives here, not in the racy TripDetailService fetchers).
            let ongoing = ongoingTrips
            await cache.keepOnly(tripIds: Set(ongoing.map { $0.id }))
            for summary in ongoing {
                await cache.saveSummary(tripId: summary.id, summary)
            }
        } catch {
            print("TripService.listMyTrips error: \(error)")
            if isOfflineError(error) {
                let cached = await cache.loadAll().compactMap { $0.summary }
                if !cached.isEmpty {
                    ongoingTrips = cached
                    planningTrips = []
                    endedTrips = []
                    isServingCachedData = true
                    return
                }
            }
            self.error = String(localized: "Failed to load trips")
        }
    }

    func joinTrip(inviteCode: String) async throws -> TripDto {
        let response = try await client.joinTrip(.init(path: .init(inviteCode: inviteCode)))
        return try response.ok.body.json
    }

    func fetchInvitePreview(inviteCode: String) async throws -> InvitePreviewDto {
        let response = try await client.getInvitePreview(
            .init(path: .init(inviteCode: inviteCode))
        )
        return try response.ok.body.json
    }

    func createTrip(
        name: String,
        cityId: Int? = nil,
        stateId: Int? = nil,
        countryId: Int? = nil
    ) async throws -> TripDto {
        isCreating = true
        error = nil
        defer { isCreating = false }

        do {
            let response = try await client.createTrip(
                .init(body: .json(.init(
                    name: name,
                    cityId: cityId,
                    stateId: stateId,
                    countryId: countryId
                )))
            )
            return try response.created.body.json
        } catch {
            print("TripService.createTrip error: \(error)")
            self.error = String(localized: "Failed to create trip")
            throw error
        }
    }

    func inviteMembers(tripId: Int, userIds: [Int]) async throws {
        guard !userIds.isEmpty else { return }

        do {
            let response = try await client.inviteMembers(
                .init(
                    path: .init(id: tripId),
                    body: .json(.init(userIds: userIds.map { Double($0) }))
                )
            )
            _ = try response.created.body.json
        } catch {
            print("TripService.inviteMembers error: \(error)")
            throw error
        }
    }
}
