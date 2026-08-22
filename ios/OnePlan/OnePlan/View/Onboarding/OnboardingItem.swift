//
//  OnboardingItem.swift
//  OnePlan
//

import SwiftUI

struct OnboardingItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
    let imageName: String
    var zoomScale: CGFloat = 1.0
    var zoomAnchor: UnitPoint = .center
}

extension OnboardingItem {
    // Titles/subtitles render via `Text(item.title)` (a `String`), so they are
    // resolved with `String(localized:)` rather than auto-localized literals.
    static let defaultItems: [OnboardingItem] = [
        OnboardingItem(
            id: 0,
            title: String(localized: "Welcome to One Plan", comment: "Onboarding slide 1 title"),
            subtitle: "",
            imageName: "welcome-to-oneplan",
        ),
        OnboardingItem(
            id: 1,
            title: String(localized: "Track Group Expenses", comment: "Onboarding slide 2 title"),
            subtitle: String(localized: "Keep every shared expense in one place\nand see who paid what, instantly.", comment: "Onboarding slide 2 subtitle"),
            imageName: "track-group-expense",
        ),
        OnboardingItem(
            id: 2,
            title: String(localized: "Plan Your Trip Together", comment: "Onboarding slide 3 title"),
            subtitle: String(localized: "Organize destinations, schedules, and trip\ndetails with your group in one smooth flow.", comment: "Onboarding slide 3 subtitle"),
            imageName: "plan-your-trip",
            zoomScale: 1.4,
            zoomAnchor: .top
        ),
        OnboardingItem(
            id: 3,
            title: String(localized: "Turn videos into place lists", comment: "Onboarding slide 4 title"),
            subtitle: String(localized: "Saw a viral café or hidden gem? Drop the link and save every place to your Board.", comment: "Onboarding slide 4 subtitle"),
            imageName: "board-extract-video",
            zoomScale: 1.6,
            zoomAnchor: .top
        ),
        OnboardingItem(
            id: 4,
            title: String(localized: "Explore Plans on Market", comment: "Onboarding slide 5 title"),
            subtitle: String(localized: "Browse ready-made travel plans from the\ncommunity and apply them in seconds.", comment: "Onboarding slide 5 subtitle"),
            imageName: "explore-plan-market"
        ),
        OnboardingItem(
            id: 5,
            title: String(localized: "Scan Bills with AI", comment: "Onboarding slide 6 title"),
            subtitle: String(localized: "Snap a receipt and let AI detect items,\ntotals, and split details automatically.", comment: "Onboarding slide 6 subtitle"),
            imageName: "scan-bills-ai",
            zoomScale: 1.2,
            zoomAnchor: .bottom
        ),
        OnboardingItem(
            id: 6,
            title: String(localized: "Settle Up with Ease", comment: "Onboarding slide 7 title"),
            subtitle: String(localized: "Wrap up the trip by calculating balances\nand seeing exactly who owes whom.", comment: "Onboarding slide 7 subtitle"),
            imageName: "settle-with-ease",
            zoomScale: 1.4,
            zoomAnchor: .top
        )
    ]
}
