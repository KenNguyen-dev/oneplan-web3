//
//  RealtimeService.swift
//  OnePlan
//

import Foundation

typealias ChatMessageDto = Components.Schemas.ChatMessageDto
typealias ChatMessageListDto = Components.Schemas.ChatMessageListDto
typealias MarkMessagesSeenDto = Components.Schemas.MarkMessagesSeenDto

@MainActor
@Observable
final class RealtimeService {
    enum TripInviteSource {
        case websocket
        case deepLink
        case api
    }

    struct TripInviteState: Identifiable, Equatable, Codable {
        let inviteCode: String
        let tripName: String
        let coverImageUrl: String?
        let invitedByDisplayName: String

        var id: String { inviteCode }
    }

    struct TripInvitePresentation: Identifiable, Equatable {
        let id = UUID()
        let invite: TripInviteState
    }

    struct ChatThreadSummary {
        var latestMessage: ChatMessageDto?
        var isLoading = false
        var lastRefreshedAt: Date?
        var lastSeenMessageId: Int?
    }

    private struct TripInviteSocketPayload: Decodable {
        let inviteCode: String
        let tripName: String
        let coverImageUrl: String?
        let invitedByDisplayName: String
    }

    private struct TripRealtimeSocketPayload: Decodable {
        let tripId: Int
    }

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    // MARK: - Chat State

    var messages: [ChatMessageDto] = []
    var threadSummaries: [Int: ChatThreadSummary] = [:]
    var connectionState: ConnectionState = .disconnected
    var isLoadingHistory = false
    var isLoadingMore = false
    var isSending = false
    var error: String?
    var hasMoreHistory: Bool { nextCursor != nil }

    // MARK: - Friend Request State

    var latestFriendRequest: FriendRequestDto?

    // MARK: - Trip Invite State

    var pendingTripInvites: [TripInviteState] = []
    var activeTripInvitePresentation: TripInvitePresentation?
    var shouldPlayTripInviteOpenSound = false

    // MARK: - Private

    private var client: Client { APIClient.shared }
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var currentTripId: Int?
    private var subscribedTripRoomIds: Set<Int> = []
    private var nextCursor: Int?
    private var knownMessageIds: Set<Int> = []
    private var intentionalDisconnect = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let threadSummaryCacheTTL: TimeInterval = 60
    private var autoPresentationQueue: [String] = []
    private var websocketSoundInviteCodes: Set<String> = []
    private let persistedTripInvitesKey = "oneplan.pendingTripInvites"

    init() {
        pendingTripInvites = loadPersistedTripInvites()
        // Reconnect when connectivity returns rather than burning reconnect
        // attempts while offline (see scheduleReconnect gating). The observer
        // captures `weak self`; this service lives for the app's lifetime, so
        // no explicit removal is needed.
        NotificationCenter.default.addObserver(
            forName: .networkBecameReachable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleNetworkBecameReachable()
            }
        }
    }

    private func handleNetworkBecameReachable() {
        guard !intentionalDisconnect, webSocketTask == nil else { return }
        reconnectAttempts = 0
        connectWebSocket()
    }

    // MARK: - Socket Lifecycle

    func connectSocket() {
        guard webSocketTask == nil else { return }
        intentionalDisconnect = false
        reconnectAttempts = 0
        connectWebSocket()
    }

    func disconnectSocket() {
        intentionalDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        currentTripId = nil
        subscribedTripRoomIds.removeAll()
        messages = []
        threadSummaries = [:]
        knownMessageIds = []
        nextCursor = nil
        connectionState = .disconnected
    }

    // MARK: - Trip Invite Presentation

    func receiveTripInvite(
        inviteCode: String,
        tripName: String,
        coverImageUrl: String?,
        invitedByDisplayName: String,
        source: TripInviteSource = .websocket
    ) {
        let invite = TripInviteState(
            inviteCode: inviteCode,
            tripName: tripName,
            coverImageUrl: coverImageUrl,
            invitedByDisplayName: invitedByDisplayName
        )

        if let existingIndex = pendingTripInvites.firstIndex(where: { $0.inviteCode == inviteCode }) {
            pendingTripInvites[existingIndex] = invite
        } else {
            pendingTripInvites.append(invite)
        }

        let isCurrentlyPresented = activeTripInvitePresentation?.invite.inviteCode == inviteCode
        if !autoPresentationQueue.contains(inviteCode) && !isCurrentlyPresented {
            autoPresentationQueue.append(inviteCode)
        }

        if source == .websocket {
            websocketSoundInviteCodes.insert(inviteCode)
        } else {
            websocketSoundInviteCodes.remove(inviteCode)
        }

        persistPendingTripInvites()
        presentNextTripInviteIfNeeded()
    }

    func presentTripInvite(inviteCode: String) {
        guard let invite = pendingTripInvites.first(where: { $0.inviteCode == inviteCode }) else {
            return
        }
        activeTripInvitePresentation = TripInvitePresentation(invite: invite)
        shouldPlayTripInviteOpenSound = false
    }

    func dismissActiveTripInvite() {
        activeTripInvitePresentation = nil
        shouldPlayTripInviteOpenSound = false
        presentNextTripInviteIfNeeded()
    }

    func refreshPendingTripInvites() async {
        do {
            let response = try await client.listPendingTripInvites(.init())
            let invites = try response.ok.body.json
            for invite in invites {
                receiveTripInvite(
                    inviteCode: invite.inviteCode,
                    tripName: invite.tripName,
                    coverImageUrl: invite.coverImageUrl,
                    invitedByDisplayName: invite.invitedByDisplayName,
                    source: .api
                )
            }
        } catch {
            print("RealtimeService.refreshPendingTripInvites error: \(error)")
        }
    }

    func resolveTripInvite(inviteCode: String) {
        pendingTripInvites.removeAll { $0.inviteCode == inviteCode }
        autoPresentationQueue.removeAll { $0 == inviteCode }
        websocketSoundInviteCodes.remove(inviteCode)
        if activeTripInvitePresentation?.invite.inviteCode == inviteCode {
            activeTripInvitePresentation = nil
        }
        shouldPlayTripInviteOpenSound = false
        persistPendingTripInvites()
        presentNextTripInviteIfNeeded()
    }

    // MARK: - Trip Room Management

    func joinTrip(tripId: Int) async {
        if let old = currentTripId, old != tripId {
            leaveTrip(tripId: old)
        }
        currentTripId = tripId
        messages = []
        knownMessageIds = []
        nextCursor = nil
        error = nil

        await loadInitialHistory(tripId: tripId)
        sendWebSocketEvent(event: "joinTrip", data: ["tripId": tripId])
    }

    func leaveTrip(tripId: Int) {
        if currentTripId == tripId {
            sendWebSocketEvent(event: "leaveTrip", data: ["tripId": tripId])
            currentTripId = nil
            messages = []
            knownMessageIds = []
            nextCursor = nil
        }
    }

    func joinTripRoom(tripId: Int) {
        subscribedTripRoomIds.insert(tripId)
        sendWebSocketEvent(event: "joinTrip", data: ["tripId": tripId])
    }

    func leaveTripRoom(tripId: Int) {
        subscribedTripRoomIds.remove(tripId)
        if currentTripId != tripId {
            sendWebSocketEvent(event: "leaveTrip", data: ["tripId": tripId])
        }
    }

    func syncTripSeenState(from trips: [TripSummaryDto]) {
        for trip in trips {
            var summary = threadSummaries[trip.id] ?? ChatThreadSummary()
            summary.lastSeenMessageId = Self.maxSeenMessageId(
                summary.lastSeenMessageId,
                trip.lastSeenChatMessageId
            )
            threadSummaries[trip.id] = summary
        }
    }

    func loadThreadSummaries(tripIds: [Int], force: Bool = false) async {
        let uniqueTripIds = Array(Set(tripIds)).sorted()
        let now = Date()
        var tripIdsToLoad: [Int] = []

        for tripId in uniqueTripIds {
            var summary = threadSummaries[tripId] ?? ChatThreadSummary()
            let isFresh = summary.lastRefreshedAt.map {
                now.timeIntervalSince($0) < threadSummaryCacheTTL
            } ?? false

            guard force || (!summary.isLoading && !isFresh) else {
                threadSummaries[tripId] = summary
                continue
            }

            summary.isLoading = true
            threadSummaries[tripId] = summary
            tripIdsToLoad.append(tripId)
        }

        let client = self.client

        for batch in tripIdsToLoad.chunked(into: 4) {
            let results = await withTaskGroup(
                of: (Int, Result<ChatMessageDto?, Error>).self,
                returning: [(Int, Result<ChatMessageDto?, Error>)].self
            ) { group in
                for tripId in batch {
                    group.addTask {
                        do {
                            let response = try await client.listMessages(.init(
                                path: .init(tripId: tripId),
                                query: .init(take: 1)
                            ))
                            let result = try response.ok.body.json
                            return (tripId, .success(result.data.first))
                        } catch {
                            return (tripId, .failure(error))
                        }
                    }
                }

                var batchResults: [(Int, Result<ChatMessageDto?, Error>)] = []
                for await result in group {
                    batchResults.append(result)
                }
                return batchResults
            }

            let refreshedAt = Date()
            for (tripId, result) in results {
                var summary = threadSummaries[tripId] ?? ChatThreadSummary()
                summary.isLoading = false

                switch result {
                case .success(let latestMessage):
                    summary.latestMessage = latestMessage
                    summary.lastRefreshedAt = refreshedAt
                case .failure:
                    break
                }

                threadSummaries[tripId] = summary
            }
        }
    }

    func loadMoreHistory() async {
        guard let cursor = nextCursor, let tripId = currentTripId else { return }
        guard !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await client.listMessages(.init(
                path: .init(tripId: tripId),
                query: .init(cursor: cursor, take: 30)
            ))
            let result = try response.ok.body.json
            let older = result.data.reversed()
            var newMessages: [ChatMessageDto] = []
            for msg in older {
                if !knownMessageIds.contains(msg.id) {
                    knownMessageIds.insert(msg.id)
                    newMessages.append(msg)
                }
            }
            messages.insert(contentsOf: newMessages, at: 0)
            nextCursor = result.nextCursor
        } catch {
            self.error = String(localized: "Failed to load more messages")
        }
    }

    func sendMessage(content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000 else { return }
        guard let tripId = currentTripId else { return }

        isSending = true
        sendWebSocketEvent(event: "sendMessage", data: [
            "tripId": tripId,
            "type": "TEXT",
            "content": trimmed,
        ])
        isSending = false
    }

    func sendImageMessage(objectKey: String) {
        let trimmedObjectKey = objectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedObjectKey.isEmpty else { return }
        guard let tripId = currentTripId else { return }

        isSending = true
        sendWebSocketEvent(event: "sendMessage", data: [
            "tripId": tripId,
            "type": "IMAGE",
            "content": "",
            "imageObjectKey": trimmedObjectKey,
        ])
        isSending = false
    }

    func markTripSeen(tripId: Int, messageId: Int) async {
        let currentSeenMessageId = threadSummaries[tripId]?.lastSeenMessageId ?? 0
        guard messageId > currentSeenMessageId else { return }

        do {
            let response = try await client.markMessagesSeen(.init(
                path: .init(tripId: tripId),
                body: .json(MarkMessagesSeenDto(messageId: messageId))
            ))
            _ = try response.noContent

            var summary = threadSummaries[tripId] ?? ChatThreadSummary()
            summary.lastSeenMessageId = messageId
            threadSummaries[tripId] = summary
            await AppBadgeService.shared.clearBadge()
        } catch {
            self.error = String(localized: "Failed to update seen state")
        }
    }

    func previewText(for tripId: Int) -> String? {
        Self.previewText(from: threadSummaries[tripId]?.latestMessage)
    }

    func previewDateText(for tripId: Int) -> String {
        guard let createdAt = threadSummaries[tripId]?.latestMessage?.createdAt else {
            return ""
        }
        return Self.previewDateText(from: createdAt)
    }

    func isTripUnread(
        tripId: Int,
        serverSeenMessageId: Int?,
        currentUserId: Int?
    ) -> Bool {
        guard let currentUserId,
              let latestMessage = threadSummaries[tripId]?.latestMessage
        else {
            return false
        }

        if latestMessage.senderId == currentUserId {
            return false
        }

        let seenMessageId = Self.maxSeenMessageId(
            threadSummaries[tripId]?.lastSeenMessageId,
            serverSeenMessageId
        ) ?? 0
        return latestMessage.id > seenMessageId
    }

    // MARK: - REST

    private func loadInitialHistory(tripId: Int) async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            let response = try await client.listMessages(.init(
                path: .init(tripId: tripId),
                query: .init(take: 30)
            ))
            let result = try response.ok.body.json
            let sorted = result.data.reversed()
            for msg in sorted {
                appendMessageIfNew(msg)
            }
            nextCursor = result.nextCursor
            touchThreadSummary(tripId: tripId)
        } catch {
            self.error = String(localized: "Failed to load messages")
        }
    }

    // MARK: - WebSocket

    private func connectWebSocket() {
        guard let token = AuthTokenStore.shared.accessToken else {
            error = String(localized: "Not authenticated")
            return
        }

        connectionState = .connecting

        let wsBase = APIEnvironment.current.baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        guard let url = URL(string: "\(wsBase)/realtime") else {
            error = String(localized: "Invalid WebSocket URL")
            connectionState = .disconnected
            return
        }
        // Send the token in the Authorization header on the WebSocket upgrade
        // request. Never put it in the URL query — proxies and CDNs log URLs.
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        connectionState = .connected
        reconnectAttempts = 0

        if let tripId = currentTripId {
            sendWebSocketEvent(event: "joinTrip", data: ["tripId": tripId])
        }
        for tripId in subscribedTripRoomIds where tripId != currentTripId {
            sendWebSocketEvent(event: "joinTrip", data: ["tripId": tripId])
        }

        startReceiveLoop()
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let task = self.webSocketTask else { break }
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        self.handleIncomingMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleIncomingMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        self.connectionState = .disconnected
                        self.scheduleReconnect()
                    }
                    break
                }
            }
        }
    }

    private func handleIncomingMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String
        else { return }

        switch event {
        case "newMessage":
            guard let msgData = json["data"],
                  let msgJson = try? JSONSerialization.data(withJSONObject: msgData),
                  let msg = try? JSONDecoder().decode(ChatMessageDto.self, from: msgJson)
            else { return }
            handleIncomingChatMessage(msg)

        case "friendRequestReceived":
            guard let reqData = json["data"],
                  let reqJson = try? JSONSerialization.data(withJSONObject: reqData),
                  let request = try? JSONDecoder().decode(FriendRequestDto.self, from: reqJson)
            else { return }
            latestFriendRequest = request

        case "friendRequestAccepted":
            break

        case "tripInviteReceived":
            guard let inviteData = json["data"],
                  let inviteJson = try? JSONSerialization.data(withJSONObject: inviteData),
                  let invitePayload = try? JSONDecoder().decode(
                      TripInviteSocketPayload.self,
                      from: inviteJson
                  )
            else { return }

            receiveTripInvite(
                inviteCode: invitePayload.inviteCode,
                tripName: invitePayload.tripName,
                coverImageUrl: invitePayload.coverImageUrl,
                invitedByDisplayName: invitePayload.invitedByDisplayName,
                source: .websocket
            )

        case "tripEnded":
            handleTripRealtimeEvent(
                json["data"],
                notificationName: .tripRealtimeEnded
            )

        case "tripDeleted":
            handleTripRealtimeEvent(
                json["data"],
                notificationName: .tripRealtimeDeleted
            )

        case "tripSettlementUpdated":
            handleTripRealtimeEvent(
                json["data"],
                notificationName: .tripSettlementUpdated
            )

        case "tripMemberRoleUpdated":
            handleTripRealtimeEvent(
                json["data"],
                notificationName: .tripMemberRoleUpdated
            )

        case "vaultBalanceChanged":
            // Carries who moved the money and how much, when there is somebody
            // to name. A balance that changes on its own is a change nobody
            // notices, and the member who did it is not the one who needs told.
            handleVaultBalanceChanged(json["data"])

        case "vaultApprovalRequested":
            // Carries the amount and the recipient, unlike the other trip
            // events, because a member has to decide whether to sign it — a
            // silent refresh would leave them to notice a new row on their own.
            handleVaultApprovalRequested(json["data"])

        case "vaultSettlementUpdated":
            handleVaultSettlementUpdated(json["data"])

        case "tripEndRequestUpdated":
            handleTripEndRequestUpdated(json["data"])

        case "vaultLeaveRequested":
            handleVaultLeaveRequested(json["data"])

        case "tripMemberRemoved":
            handleTripMemberRemoved(json["data"])

        case "error":
            if let errData = json["data"] as? [String: Any],
               let message = errData["message"] as? String {
                error = message
            }

        default:
            break
        }
    }

    private func handleVaultBalanceChanged(_ eventData: Any?) {
        guard let data = eventData as? [String: Any],
              let tripId = data["tripId"] as? Int
        else { return }

        var info: [String: Any] = ["tripId": tripId]
        // Absent for a refresh with no author, such as the reconcile job
        // finishing something off.
        if let kind = data["kind"] as? String {
            info["kind"] = kind
            info["actorUserId"] = data["actorUserId"] as? Int ?? 0
            info["actorName"] = data["actorName"] as? String ?? ""
            info["amountMicro"] = data["amountMicro"] as? String ?? "0"
        }
        NotificationCenter.default.post(
            name: .vaultBalanceChanged,
            object: nil,
            userInfo: info
        )
    }

    private func handleVaultApprovalRequested(_ eventData: Any?) {
        guard let data = eventData as? [String: Any],
              let tripId = data["tripId"] as? Int,
              let vaultTransactionId = data["vaultTransactionId"] as? Int
        else { return }

        NotificationCenter.default.post(
            name: .vaultApprovalRequested,
            object: nil,
            userInfo: [
                "tripId": tripId,
                "vaultTransactionId": vaultTransactionId,
                // Strings on the wire: the amount is dong, which outgrows what a
                // JSON number carries exactly.
                "amountVnd": data["amountVnd"] as? String ?? "",
                "recipientName": data["recipientName"] as? String ?? "",
                "proposedByUserId": data["proposedByUserId"] as? Int ?? 0,
                // Absent means the trip lets any member approve. Distinct from
                // an empty list, which the server never sends.
                "approverUserIds": data["approverUserIds"] as? [Int] as Any,
            ]
        )
    }

    private func handleVaultSettlementUpdated(_ eventData: Any?) {
        guard let data = eventData as? [String: Any],
              let tripId = data["tripId"] as? Int
        else { return }

        NotificationCenter.default.post(
            name: .vaultSettlementUpdated,
            object: nil,
            userInfo: ["tripId": tripId]
        )
    }

    private func handleTripEndRequestUpdated(_ eventData: Any?) {
        guard let data = eventData as? [String: Any],
              let tripId = data["tripId"] as? Int
        else { return }

        var info: [String: Any] = [
            "tripId": tripId,
            "status": data["status"] as? String ?? "",
            "approvedCount": data["approvedCount"] as? Int ?? 0,
            "memberCount": data["memberCount"] as? Int ?? 0,
        ]
        if let deniedBy = data["deniedByUserId"] as? Int {
            info["deniedByUserId"] = deniedBy
        }
        NotificationCenter.default.post(
            name: .tripEndRequestUpdated,
            object: nil,
            userInfo: info
        )
    }

    private func handleVaultLeaveRequested(_ eventData: Any?) {
        guard let data = eventData as? [String: Any],
              let tripId = data["tripId"] as? Int
        else { return }

        var info: [String: Any] = ["tripId": tripId]
        if let userId = data["userId"] as? Int {
            info["userId"] = userId
        }
        NotificationCenter.default.post(
            name: .vaultLeaveRequested,
            object: nil,
            userInfo: info
        )
    }

    private func handleTripMemberRemoved(_ eventData: Any?) {
        guard let data = eventData as? [String: Any],
              let tripId = data["tripId"] as? Int
        else { return }

        var info: [String: Any] = ["tripId": tripId]
        if let userId = data["userId"] as? Int {
            info["userId"] = userId
        }
        if let displayName = data["displayName"] as? String {
            info["displayName"] = displayName
        }
        NotificationCenter.default.post(
            name: .tripMemberRemoved,
            object: nil,
            userInfo: info
        )
    }

    private func handleTripRealtimeEvent(
        _ eventData: Any?,
        notificationName: Notification.Name
    ) {
        guard let eventData,
              let eventJson = try? JSONSerialization.data(withJSONObject: eventData),
              let payload = try? JSONDecoder().decode(
                  TripRealtimeSocketPayload.self,
                  from: eventJson
              )
        else { return }

        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: ["tripId": payload.tripId]
        )
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        guard !intentionalDisconnect, reconnectAttempts < maxReconnectAttempts else { return }

        // Don't retry while offline — it just burns the attempt budget. The
        // .networkBecameReachable observer reconnects when connectivity returns.
        guard NetworkMonitor.shared.isOnline else {
            connectionState = .disconnected
            return
        }

        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 2.0, 30.0)

        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, !intentionalDisconnect else { return }
            connectionState = .reconnecting
            webSocketTask = nil
            connectWebSocket()
        }
    }

    // MARK: - Helpers

    private func sendWebSocketEvent(event: String, data: [String: Any]) {
        let payload: [String: Any] = ["event": event, "data": data]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: jsonData, encoding: .utf8)
        else { return }

        webSocketTask?.send(.string(text)) { error in
            if let error {
                print("RealtimeService.sendWebSocketEvent error: \(error)")
            }
        }
    }

    private func appendMessageIfNew(_ message: ChatMessageDto) {
        guard !knownMessageIds.contains(message.id) else { return }
        knownMessageIds.insert(message.id)
        messages.append(message)
        updateLatestMessageSummary(with: message)
    }

    private func handleIncomingChatMessage(_ message: ChatMessageDto) {
        updateLatestMessageSummary(with: message)

        guard currentTripId == message.tripId else { return }
        guard !knownMessageIds.contains(message.id) else { return }

        knownMessageIds.insert(message.id)
        messages.append(message)
    }

    private func updateLatestMessageSummary(with message: ChatMessageDto) {
        var summary = threadSummaries[message.tripId] ?? ChatThreadSummary()

        if let latestMessage = summary.latestMessage, latestMessage.id >= message.id {
            summary.lastRefreshedAt = Date()
            threadSummaries[message.tripId] = summary
            return
        }

        summary.latestMessage = message
        summary.lastRefreshedAt = Date()
        summary.isLoading = false
        threadSummaries[message.tripId] = summary
    }

    private func touchThreadSummary(tripId: Int) {
        var summary = threadSummaries[tripId] ?? ChatThreadSummary()
        summary.lastRefreshedAt = Date()
        summary.isLoading = false
        threadSummaries[tripId] = summary
    }

    private func presentNextTripInviteIfNeeded() {
        guard activeTripInvitePresentation == nil else { return }

        while !autoPresentationQueue.isEmpty {
            let nextInviteCode = autoPresentationQueue.removeFirst()
            if let invite = pendingTripInvites.first(where: { $0.inviteCode == nextInviteCode }) {
                activeTripInvitePresentation = TripInvitePresentation(invite: invite)
                shouldPlayTripInviteOpenSound = websocketSoundInviteCodes.remove(nextInviteCode) != nil
                return
            }
        }

        shouldPlayTripInviteOpenSound = false
    }

    private func persistPendingTripInvites() {
        let defaults = UserDefaults.standard
        guard !pendingTripInvites.isEmpty else {
            defaults.removeObject(forKey: persistedTripInvitesKey)
            return
        }

        if let data = try? JSONEncoder().encode(pendingTripInvites) {
            defaults.set(data, forKey: persistedTripInvitesKey)
        }
    }

    private func loadPersistedTripInvites() -> [TripInviteState] {
        guard
            let data = UserDefaults.standard.data(forKey: persistedTripInvitesKey),
            let invites = try? JSONDecoder().decode([TripInviteState].self, from: data)
        else {
            return []
        }
        return invites
    }

    private static func previewText(from message: ChatMessageDto?) -> String? {
        guard let message else { return nil }

        if message._type.value1 == .IMAGE {
            return "Sent a photo"
        }

        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func previewDateText(from createdAt: String) -> String {
        guard let date = parseMessageDate(createdAt) else { return "" }
        return previewDateFormatter.string(from: date)
    }

    private static func parseMessageDate(_ value: String) -> Date? {
        if let date = iso8601WithFractionalFormatter.date(from: value) {
            return date
        }
        return iso8601Formatter.date(from: value)
    }

    private static func maxSeenMessageId(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private static let iso8601WithFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()

    private static let previewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }

        var chunks: [[Element]] = []
        var index = startIndex

        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }

        return chunks
    }
}
