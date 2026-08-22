//
//  ActiveChatTracker.swift
//  OnePlan
//

import Foundation

@MainActor
@Observable
final class ActiveChatTracker {
    static let shared = ActiveChatTracker()
    var activeTripId: Int?

    private init() {}
}
