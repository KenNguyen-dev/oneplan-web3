//
//  OnboardingManager.swift
//  OnePlan
//

import SwiftUI

@MainActor
@Observable
final class OnboardingManager {
    private let hasSeenOnboardingKey = "hasSeenOnboarding"
    private let trialOfferDeadlineKey = "trialOfferDeadline"

    var hasSeenOnboarding: Bool
    /// Persisted end of the limited-time free-trial promo (FreeTrialView)
    /// window. nil until the promo is first shown; once `Date() >= deadline`
    /// the promo is never auto-presented again. Backs the on-screen countdown
    /// so it survives app relaunch instead of resetting on every open.
    var trialOfferDeadline: Date?

    init() {
        hasSeenOnboarding = UserDefaults.standard.bool(forKey: hasSeenOnboardingKey)
        trialOfferDeadline = UserDefaults.standard.object(forKey: trialOfferDeadlineKey) as? Date
    }

    func completeOnboarding() {
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: hasSeenOnboardingKey)
    }

    /// Returns the existing promo deadline, or starts the window now
    /// (`now + window`) and persists it on first call. Call only when actually
    /// about to present, so the clock starts at the first real presentation.
    func startTrialOfferWindowIfNeeded(_ window: TimeInterval = 60 * 60) -> Date {
        if let trialOfferDeadline { return trialOfferDeadline }
        let deadline = Date().addingTimeInterval(window)
        trialOfferDeadline = deadline
        UserDefaults.standard.set(deadline, forKey: trialOfferDeadlineKey)
        return deadline
    }

    /// For testing/debugging: reset onboarding state
    func resetOnboarding() {
        hasSeenOnboarding = false
        UserDefaults.standard.set(false, forKey: hasSeenOnboardingKey)
        trialOfferDeadline = nil
        UserDefaults.standard.removeObject(forKey: trialOfferDeadlineKey)
    }
}
