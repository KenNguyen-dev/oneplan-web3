//
//  AppBadgeService.swift
//  OnePlan
//

import UserNotifications

@MainActor
final class AppBadgeService {
    static let shared = AppBadgeService()

    private init() {}

    func clearBadge() async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(0)
        } catch {
            print("AppBadgeService.clearBadge error: \(error)")
        }
    }
}
