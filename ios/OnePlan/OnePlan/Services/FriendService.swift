//
//  FriendService.swift
//  OnePlan
//

import Foundation

typealias FriendPreviewDto = Components.Schemas.FriendPreviewDto
typealias FriendProfileDto = Components.Schemas.FriendProfileDto
typealias FriendProfileFriendEntryDto = Components.Schemas.FriendProfileFriendEntryDto
typealias FriendRequestDto = Components.Schemas.FriendRequestDto
typealias FriendDto = Components.Schemas.FriendDto

@MainActor
@Observable
final class FriendService {
    var friends: [FriendDto] = []
    var pendingRequests: [FriendRequestDto] = []
    var profile: FriendProfileDto?
    var isLoadingFriends = false
    var isLoadingRequests = false
    var isLoadingProfile = false
    var isSendingRequest = false
    var error: String?

    private var client: Client { APIClient.shared }

    func reset() {
        friends = []
        pendingRequests = []
        profile = nil
        error = nil
    }

    // MARK: - User Profile

    func loadUserProfile(userId: Int) async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }

        do {
            let response = try await client.getUserFriendProfile(
                .init(path: .init(userId: userId))
            )
            profile = try response.ok.body.json
        } catch {
            print("FriendService.loadUserProfile error: \(error)")
            self.error = String(localized: "Failed to load profile")
        }
    }

    // MARK: - Preview

    func previewFriend(code: String) async throws -> FriendPreviewDto {
        let response = try await client.previewFriend(
            .init(path: .init(friendCode: code))
        )
        return try response.ok.body.json
    }

    // MARK: - Send Request

    func sendRequest(friendCode: String) async throws {
        isSendingRequest = true
        defer { isSendingRequest = false }

        let _ = try await client.sendFriendRequest(
            .init(body: .json(.init(friendCode: friendCode)))
        )
    }

    // MARK: - Respond to Request

    func respondToRequest(id: Int, accept: Bool) async throws {
        let _ = try await client.respondToFriendRequest(
            .init(
                path: .init(id: id),
                body: .json(.init(accept: accept))
            )
        )

        // Remove from local list
        pendingRequests.removeAll { $0.id == id }

        // Reload friends if accepted
        if accept {
            await loadFriends()
        }
    }

    // MARK: - Cancel Sent Request

    func cancelSentRequest(friendCode: String) async throws {
        let _ = try await client.cancelSentFriendRequest(
            .init(path: .init(friendCode: friendCode))
        )
    }

    // MARK: - Friends List

    func loadFriends() async {
        isLoadingFriends = true
        defer { isLoadingFriends = false }

        do {
            let response = try await client.listFriends(.init())
            friends = try response.ok.body.json
        } catch {
            print("FriendService.loadFriends error: \(error)")
            self.error = String(localized: "Failed to load friends")
        }
    }

    // MARK: - Pending Requests

    func loadPendingRequests() async {
        isLoadingRequests = true
        defer { isLoadingRequests = false }

        do {
            let response = try await client.listFriendRequests(.init())
            pendingRequests = try response.ok.body.json
        } catch {
            print("FriendService.loadPendingRequests error: \(error)")
            self.error = String(localized: "Failed to load friend requests")
        }
    }

    // MARK: - Unfriend

    func unfriend(friendshipId: Int) async throws {
        let _ = try await client.unfriend(
            .init(path: .init(friendshipId: friendshipId))
        )
        friends.removeAll { $0.friendshipId == friendshipId }
    }
}
