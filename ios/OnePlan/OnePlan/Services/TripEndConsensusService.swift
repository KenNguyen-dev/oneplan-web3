import Foundation
import OpenAPIRuntime

typealias TripEndRequestDto = Components.Schemas.TripEndRequestDto
typealias TripEndReviewDto = Components.Schemas.TripEndReviewDto
typealias TripEndVoteDecision = Components.Schemas.TripEndVoteDecision
typealias TripEndRequestStatus = Components.Schemas.TripEndRequestStatus

/// Off-chain Approve/Deny flow for ending a vault trip.
@Observable
@MainActor
final class TripEndConsensusService {
    static let shared = TripEndConsensusService()

    private var client: Client { APIClient.shared }

    private init() {}

    /// Creator starts (or restarts after a deny) the end-trip vote.
    func requestEnd(tripId: Int) async throws -> TripEndRequestDto {
        let response = try await client.requestTripEnd(
            .init(path: .init(id: tripId))
        )
        switch response {
        case .ok(let ok):
            return try ok.body.json
        case .created(let created):
            return try created.body.json
        case .forbidden:
            throw ConsensusError.message(
                String(localized: "Only the trip creator can end this trip.")
            )
        case .conflict:
            throw ConsensusError.alreadyPending
        case .undocumented(statusCode: let code, _):
            throw ConsensusError.message(
                String(localized: "Failed to request end trip (error \(code)).")
            )
        }
    }

    /// Current request, or nil when none exists (404).
    func getRequest(tripId: Int) async throws -> TripEndRequestDto? {
        let response = try await client.getTripEndRequest(
            .init(path: .init(id: tripId))
        )
        switch response {
        case .ok(let ok):
            return try ok.body.json
        case .notFound:
            return nil
        case .undocumented(statusCode: let code, _):
            throw ConsensusError.message(
                String(localized: "Failed to load end request (error \(code)).")
            )
        }
    }

    func getReview(tripId: Int) async throws -> TripEndReviewDto {
        try await client
            .getTripEndReview(.init(path: .init(id: tripId)))
            .ok.body.json
    }

    func vote(
        tripId: Int,
        decision: TripEndVoteDecision
    ) async throws -> TripEndRequestDto {
        try await client
            .castTripEndVote(
                .init(
                    path: .init(id: tripId),
                    body: .json(.init(decision: .init(value1: decision)))
                )
            )
            .ok.body.json
    }

    enum ConsensusError: LocalizedError {
        case alreadyPending
        case message(String)

        var errorDescription: String? {
            switch self {
            case .alreadyPending:
                return String(localized: "An end request is already waiting for approval.")
            case .message(let text):
                return text
            }
        }
    }
}
