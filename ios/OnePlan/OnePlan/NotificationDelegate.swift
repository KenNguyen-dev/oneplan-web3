//
//  NotificationDelegate.swift
//  OnePlan
//

import Observation
import UIKit
import UserNotifications

@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        let parsedTripId = NotificationPayloadParser.parseTripId(from: userInfo)

        // Suppress push if user is currently viewing this trip's chat
        if let tripId = parsedTripId {
            let activeTripId = ActiveChatTracker.shared.activeTripId
            if activeTripId == tripId {
                return []
            }
        }

        // Pin-extraction pushes are only redundant when the user is
        // literally inside ProcessPinView for THIS session — the view
        // itself transitions to a "Stream finished" state from the SSE
        // 'done' event. Any other foreground state (different tab,
        // BoardView, or even ProcessPinView for a different session)
        // should still see the banner so they find out.
        if NotificationPayloadParser.parseType(from: userInfo)
            == "pin_extraction_completed"
        {
            Task { await PinExtractionSessionService.shared.refresh() }
            let pushSessionId =
                NotificationPayloadParser
                .parsePinExtractionSessionId(from: userInfo)
            let attached = PinExtractionSessionService.shared.attachedSessionId
            if let pushSessionId, pushSessionId == attached {
                return []
            }
            return [.banner, .sound]
        }

        // The backend currently sends a fixed badge value, so avoid mutating the
        // icon badge while the app is already in the foreground.
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await AppBadgeService.shared.clearBadge()

        let userInfo = response.notification.request.content.userInfo
        let notificationType = NotificationPayloadParser.parseType(from: userInfo)

        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return
        }

        if notificationType == "trip_invite" {
            guard let inviteCode = NotificationPayloadParser.parseInviteCode(from: userInfo) else {
                print("NotificationDelegate: ignored trip_invite push without inviteCode")
                return
            }
            DeepLinkRouter.shared.queueTripInviteCode(inviteCode)
            return
        }

        if notificationType == "friend_request" {
            DeepLinkRouter.shared.queueFriendRequestTap()
            return
        }

        if notificationType == "listing_approved" || notificationType == "listing_rejected" {
            guard let listingId = NotificationPayloadParser.parseListingId(from: userInfo) else {
                print("NotificationDelegate: ignored listing push without listingId")
                return
            }
            DeepLinkRouter.shared.queueListingId(listingId)
            return
        }

        if notificationType == "trip_request_fulfilled" {
            if let listingId = NotificationPayloadParser.parseListingId(from: userInfo) {
                DeepLinkRouter.shared.queueListingId(listingId)
            } else {
                // Older pushes without a listingId just land on the Market tab.
                DeepLinkRouter.shared.queueOpenMarket()
            }
            return
        }

        if notificationType == "pin_extraction_completed" {
            guard
                let sessionId = NotificationPayloadParser.parsePinExtractionSessionId(
                    from: userInfo
                )
            else {
                print("NotificationDelegate: ignored pin extraction push without sessionId")
                return
            }
            DeepLinkRouter.shared.queuePinExtractionSessionId(sessionId)
            // Refresh in the background — the user may not actually tap
            // through to the session, but the card on BoardView should
            // reflect the latest state regardless.
            Task { await PinExtractionSessionService.shared.refresh() }
            return
        }

        if notificationType == "admin_broadcast" {
            switch userInfo["destination"] as? String {
            case "board":
                DeepLinkRouter.shared.queueOpenBoard()
            case "market":
                // Admin can attach a specific listing; older pushes (or no
                // selection) just land on the Market tab.
                if let listingId = NotificationPayloadParser.parseListingId(from: userInfo) {
                    DeepLinkRouter.shared.queueListingId(listingId)
                } else {
                    DeepLinkRouter.shared.queueOpenMarket()
                }
            default:
                break  // no destination → just open the app
            }
            return
        }

        // Engagement / marketing nudges. Record the open (server-tracked
        // ENGAGEMENT_PUSH_OPENED, client-emitted) then route to the relevant
        // screen. Types mirror the server's ENGAGEMENT_PUSH_TYPE map.
        if let notificationType, notificationType.hasPrefix("engagement_") {
            AnalyticsClient.shared.track(
                .ENGAGEMENT_PUSH_OPENED,
                properties: ["type": notificationType]
            )

            switch notificationType {
            case "engagement_new_plan":
                if let listingId = NotificationPayloadParser.parseListingId(from: userInfo) {
                    DeepLinkRouter.shared.queueListingId(listingId)
                } else {
                    DeepLinkRouter.shared.queueOpenMarket()
                }
            case "engagement_dormant":
                DeepLinkRouter.shared.queueOpenBoard()
            case "engagement_weather":
                if let tripId = NotificationPayloadParser.parseTripId(from: userInfo) {
                    DeepLinkRouter.shared.queueTripDetailId(tripId)
                }
            case "engagement_unfinished_plan":
                if let tripId = NotificationPayloadParser.parseTripId(from: userInfo) {
                    // Open the trip detail and jump straight to the Your Plan
                    // tab so the user lands in the plan editor (reuses the
                    // post-pin-attach plan-refresh one-shot).
                    DeepLinkRouter.shared.queueTripDetailId(tripId)
                    DeepLinkRouter.shared.queuePlanRefresh(tripId: tripId)
                }
            default:
                break
            }
            return
        }

        guard let tripId = NotificationPayloadParser.parseTripId(from: userInfo) else {
            print("NotificationDelegate: ignored push tap with invalid tripId payload")
            return
        }

        switch notificationType {
        case "member_left", "member_joined":
            DeepLinkRouter.shared.queueTripDetailId(tripId)
        case "plan_reminder":
            if let planItemId = NotificationPayloadParser.parsePlanItemId(from: userInfo) {
                DeepLinkRouter.shared.queuePlanItem(tripId: tripId, planItemId: planItemId)
            } else {
                DeepLinkRouter.shared.queueTripDetailId(tripId)
            }
        case nil:
            // Unknown but trip-scoped `type` (e.g. a newer engagement_* push
            // received by an older build that predates its handling) → land on
            // the trip in TripView, not the chat.
            DeepLinkRouter.shared.queueTripDetailId(tripId)
        default:
            // Unknown but trip-scoped `type` (e.g. a newer engagement_* push
            // received by an older build that predates its handling) → land on
            // the trip in TripView, not the chat.
            DeepLinkRouter.shared.queueTripDetailId(tripId)
        }
    }
}

enum NotificationPayloadParser {
    static func parseTripId(from userInfo: [AnyHashable: Any]) -> Int? {
        if let value = userInfo["tripId"] as? Int, value > 0 {
            return value
        }

        if let value = userInfo["tripId"] as? NSNumber {
            let doubleValue = value.doubleValue
            guard doubleValue > 0, doubleValue.rounded() == doubleValue else {
                return nil
            }
            return Int(doubleValue)
        }

        if let value = userInfo["tripId"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let tripId = Int(trimmed), tripId > 0 else { return nil }
            return tripId
        }

        return nil
    }

    static func parseType(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["type"] as? String
    }

    static func parseInviteCode(from userInfo: [AnyHashable: Any]) -> String? {
        guard let value = userInfo["inviteCode"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parsePlanItemId(from userInfo: [AnyHashable: Any]) -> Int? {
        if let value = userInfo["planItemId"] as? Int, value > 0 {
            return value
        }
        if let value = userInfo["planItemId"] as? NSNumber {
            let doubleValue = value.doubleValue
            guard doubleValue > 0, doubleValue.rounded() == doubleValue else {
                return nil
            }
            return Int(doubleValue)
        }
        if let value = userInfo["planItemId"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = Int(trimmed), id > 0 else { return nil }
            return id
        }
        return nil
    }

    static func parseListingId(from userInfo: [AnyHashable: Any]) -> Int? {
        if let value = userInfo["listingId"] as? Int, value > 0 {
            return value
        }
        if let value = userInfo["listingId"] as? NSNumber {
            let doubleValue = value.doubleValue
            guard doubleValue > 0, doubleValue.rounded() == doubleValue else {
                return nil
            }
            return Int(doubleValue)
        }
        if let value = userInfo["listingId"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = Int(trimmed), id > 0 else { return nil }
            return id
        }
        return nil
    }

    static func parsePinExtractionSessionId(from userInfo: [AnyHashable: Any]) -> String? {
        guard let value = userInfo["sessionId"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PlanItemDeepLink: Equatable, Hashable {
    let tripId: Int
    let planItemId: Int
}

@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()
    private(set) var pendingChatTripId: Int?
    private(set) var pendingTripDetailId: Int?
    private(set) var pendingTripInviteCode: String?
    private(set) var pendingFriendRequestTap: Bool = false
    private(set) var pendingPlanItem: PlanItemDeepLink?

    func queueChatTripId(_ tripId: Int) {
        pendingChatTripId = tripId
    }

    func consumePendingChatTripId() -> Int? {
        let value = pendingChatTripId
        pendingChatTripId = nil
        return value
    }

    func queueTripDetailId(_ tripId: Int) {
        pendingTripDetailId = tripId
    }

    func consumePendingTripDetailId() -> Int? {
        let value = pendingTripDetailId
        pendingTripDetailId = nil
        return value
    }

    private(set) var pendingListingId: Int?

    func queueListingId(_ id: Int) {
        pendingListingId = id
    }

    func consumePendingListingId() -> Int? {
        let value = pendingListingId
        pendingListingId = nil
        return value
    }

    func queueTripInviteCode(_ code: String) {
        pendingTripInviteCode = code
    }

    func consumePendingTripInviteCode() -> String? {
        let value = pendingTripInviteCode
        pendingTripInviteCode = nil
        return value
    }

    func queueFriendRequestTap() {
        pendingFriendRequestTap = true
    }

    func consumePendingFriendRequestTap() -> Bool {
        let value = pendingFriendRequestTap
        pendingFriendRequestTap = false
        return value
    }

    func queuePlanItem(tripId: Int, planItemId: Int) {
        pendingPlanItem = PlanItemDeepLink(tripId: tripId, planItemId: planItemId)
    }

    func consumePendingPlanItem() -> PlanItemDeepLink? {
        let value = pendingPlanItem
        pendingPlanItem = nil
        return value
    }

    private(set) var pendingPinExtractionSessionId: String?

    func queuePinExtractionSessionId(_ id: String) {
        pendingPinExtractionSessionId = id
    }

    func consumePendingPinExtractionSessionId() -> String? {
        let value = pendingPinExtractionSessionId
        pendingPinExtractionSessionId = nil
        return value
    }

    // Set when a fresh extraction URL arrives from the Share Extension (user
    // shared an IG/TikTok link into OnePlan). MainView observes it to switch to
    // the Board (`.chat`) tab; BoardView is the SOLE consumer and runs the link
    // through the same credit gate as a pasted link. Mirrors the session-id slot
    // above.
    private(set) var pendingPinExtractionURL: String?

    func queuePinExtractionURL(_ link: String) {
        pendingPinExtractionURL = link
    }

    func consumePendingPinExtractionURL() -> String? {
        let value = pendingPinExtractionURL
        pendingPinExtractionURL = nil
        return value
    }

    // One-shot: set by ProcessPinView when pins are attached to a trip, so the
    // TripDetailView that opens afterwards (mounts after the .openTripDetail
    // navigation, too late for a NotificationCenter post) can, at mount, jump
    // to the Your Plan tab and force-refresh its plan items. Matched on tripId
    // so it only fires for the intended trip (a different trip opening first
    // leaves the flag intact).
    private(set) var pendingPlanRefreshTripId: Int?

    func queuePlanRefresh(tripId: Int) {
        pendingPlanRefreshTripId = tripId
    }

    func consumePlanRefresh(tripId: Int) -> Bool {
        guard pendingPlanRefreshTripId == tripId else { return false }
        pendingPlanRefreshTripId = nil
        return true
    }

    // Admin broadcast destinations: tapping the push switches to the Board
    // (`.chat`) or Market tab. MainView observes and consumes these.
    private(set) var pendingOpenBoard: Bool = false
    private(set) var pendingOpenMarket: Bool = false

    func queueOpenBoard() {
        pendingOpenBoard = true
    }

    func consumePendingOpenBoard() -> Bool {
        let value = pendingOpenBoard
        pendingOpenBoard = false
        return value
    }

    func queueOpenMarket() {
        pendingOpenMarket = true
    }

    func consumePendingOpenMarket() -> Bool {
        let value = pendingOpenMarket
        pendingOpenMarket = false
        return value
    }
}
