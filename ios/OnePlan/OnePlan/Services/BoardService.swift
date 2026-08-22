//
//  BoardService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

typealias BoardDto = Components.Schemas.BoardDto
typealias BoardSummaryDto = Components.Schemas.BoardSummaryDto
typealias BoardPinDto = Components.Schemas.BoardPinDto
typealias CreateBoardDto = Components.Schemas.CreateBoardDto
typealias UpdateBoardDto = Components.Schemas.UpdateBoardDto
typealias PinInputDto = Components.Schemas.PinInputDto
typealias AddPinsToBoardDto = Components.Schemas.AddPinsToBoardDto
typealias GenerateBoardDescriptionDto = Components.Schemas.GenerateBoardDescriptionDto

extension Notification.Name {
    nonisolated(unsafe) static let boardCreated = Notification.Name("boardCreated")
    nonisolated(unsafe) static let boardUpdated = Notification.Name("boardUpdated")
    // Posted by ProcessPinView after pins are attached to a board, so BoardView
    // can pop ProcessPinView and push that board's detail. Only valid while the
    // Board tab is active (BoardView is .id(activeTab)-keyed).
    nonisolated(unsafe) static let openBoardDetail = Notification.Name("openBoardDetail")
}

@MainActor
@Observable
final class BoardService {
    static let shared = BoardService()

    var boards: [BoardSummaryDto] = []
    var isLoading = false
    var error: String?

    private var client: Client { APIClient.shared }
    private var hasLoaded = false

    func loadIfNeeded(force: Bool = false) async {
        if !force && hasLoaded { return }
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.listMyBoards(.init())
            boards = try response.ok.body.json
            hasLoaded = true
        } catch {
            print("BoardService.load error: \(error)")
            self.error = String(localized: "Failed to load boards")
        }
    }

    @discardableResult
    func createBoard(
        title: String,
        description: String? = nil,
        coverImageUrl: String? = nil,
        cityId: Int? = nil,
        stateId: Int? = nil,
        countryId: Int? = nil
    ) async throws -> BoardSummaryDto {
        let response = try await client.createBoard(
            .init(
                body: .json(
                    .init(
                        title: title,
                        description: description,
                        coverImageUrl: coverImageUrl,
                        cityId: cityId,
                        stateId: stateId,
                        countryId: countryId
                    )
                )
            )
        )
        let created = try response.created.body.json
        boards.insert(created, at: 0)
        NotificationCenter.default.post(name: .boardCreated, object: created.id)
        return created
    }

    @discardableResult
    func updateBoard(
        boardId: Int,
        title: String,
        description: String? = nil,
        cityId: Int? = nil,
        stateId: Int? = nil,
        countryId: Int? = nil
    ) async throws -> BoardSummaryDto {
        let response = try await client.updateBoard(
            .init(
                path: .init(boardId: boardId),
                body: .json(
                    .init(
                        title: title,
                        description: description,
                        cityId: cityId,
                        stateId: stateId,
                        countryId: countryId
                    )
                )
            )
        )
        // Server returns a complete BoardSummaryDto (fresh signed coverImageUrl,
        // rebuilt locationLabel, real pinCount), so replace the local entry
        // wholesale rather than mutating field-by-field.
        let updated = try response.ok.body.json
        if let idx = boards.firstIndex(where: { $0.id == boardId }) {
            boards[idx] = updated
        }
        NotificationCenter.default.post(name: .boardUpdated, object: boardId)
        return updated
    }

    func generateDescription(
        title: String,
        countryName: String,
        stateName: String? = nil,
        cityName: String? = nil
    ) async throws -> String {
        let response = try await client.generateBoardDescription(
            .init(
                body: .json(
                    .init(
                        title: title,
                        countryName: countryName,
                        stateName: stateName,
                        cityName: cityName
                    )
                )
            )
        )
        return try response.ok.body.json.description
    }

    func getBoard(boardId: Int) async throws -> BoardDto {
        let response = try await client.getBoard(.init(path: .init(boardId: boardId)))
        return try response.ok.body.json
    }

    func deletePin(boardId: Int, pinId: Int) async throws {
        let response = try await client.deleteBoardPin(
            .init(path: .init(boardId: boardId, pinId: pinId))
        )
        _ = try response.noContent
        if let idx = boards.firstIndex(where: { $0.id == boardId }) {
            let current = boards[idx]
            boards[idx] = .init(
                id: current.id,
                title: current.title,
                description: current.description,
                coverImageUrl: current.coverImageUrl,
                cityId: current.cityId,
                stateId: current.stateId,
                countryId: current.countryId,
                locationLabel: current.locationLabel,
                pinCount: max(0, current.pinCount - 1),
                createdAt: current.createdAt,
                updatedAt: current.updatedAt
            )
        }
        NotificationCenter.default.post(name: .boardUpdated, object: boardId)
    }

    func deleteBoard(boardId: Int) async throws {
        let response = try await client.deleteBoard(
            .init(path: .init(boardId: boardId))
        )
        _ = try response.noContent
        boards.removeAll { $0.id == boardId }
        NotificationCenter.default.post(name: .boardUpdated, object: boardId)
    }

    @discardableResult
    func updateLocalCoverImageUrl(
        boardId: Int,
        coverImageUrl: String
    ) -> BoardSummaryDto? {
        guard let idx = boards.firstIndex(where: { $0.id == boardId }) else {
            return nil
        }
        let current = boards[idx]
        let updated = BoardSummaryDto(
            id: current.id,
            title: current.title,
            description: current.description,
            coverImageUrl: coverImageUrl,
            cityId: current.cityId,
            stateId: current.stateId,
            countryId: current.countryId,
            locationLabel: current.locationLabel,
            pinCount: current.pinCount,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt
        )
        boards[idx] = updated
        NotificationCenter.default.post(name: .boardUpdated, object: boardId)
        return updated
    }

    /// Arrange the given board pins into a brand-new multi-day trip on the
    /// server (AI groups them by geography across `dayCount` days). Returns the
    /// freshly created trip so the caller can navigate into it.
    /// `fillGaps` lets the AI add clearly-marked suggested venues for empty
    /// meal/sightseeing slots (opt-in, defaults to false = pins only).
    func generateTrip(
        boardId: Int,
        pinIds: [Int],
        dayCount: Int,
        tripName: String,
        fillGaps: Bool = false
    ) async throws -> TripDto {
        let response = try await client.generateTripFromBoard(
            .init(
                path: .init(boardId: boardId),
                body: .json(
                    .init(
                        pinIds: pinIds,
                        dayCount: dayCount,
                        tripName: tripName,
                        fillGaps: fillGaps
                    )
                )
            )
        )
        return try response.created.body.json
    }

    @discardableResult
    func addPins(boardId: Int, pins: [PinInputDto]) async throws -> BoardDto {
        let response = try await client.addPinsToBoard(
            .init(
                path: .init(boardId: boardId),
                body: .json(.init(pins: pins))
            )
        )
        let updated = try response.ok.body.json
        if let idx = boards.firstIndex(where: { $0.id == boardId }) {
            var current = boards[idx]
            current = .init(
                id: current.id,
                title: current.title,
                description: current.description,
                coverImageUrl: current.coverImageUrl,
                cityId: current.cityId,
                stateId: current.stateId,
                countryId: current.countryId,
                locationLabel: current.locationLabel,
                pinCount: updated.pins.count,
                createdAt: current.createdAt,
                updatedAt: updated.updatedAt
            )
            boards[idx] = current
        }
        NotificationCenter.default.post(name: .boardUpdated, object: boardId)
        return updated
    }
}
