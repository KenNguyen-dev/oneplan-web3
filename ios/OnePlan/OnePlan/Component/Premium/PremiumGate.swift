//
//  PremiumGate.swift
//  OnePlan
//

import SwiftUI

/// A wrapper component that gates premium features.
/// When `allowed` is false, tapping shows the SubscriptionView paywall.
struct PremiumGate<Content: View>: View {
    @State private var showingPaywall = false

    let allowed: Bool
    let dimsWhenBlocked: Bool
    @ViewBuilder let content: () -> Content

    init(
        allowed: Bool,
        dimsWhenBlocked: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.allowed = allowed
        self.dimsWhenBlocked = dimsWhenBlocked
        self.content = content
    }

    var body: some View {
        Group {
            if allowed {
                content()
            } else {
                content()
                    .opacity(dimsWhenBlocked ? 0.6 : 1)
                    .allowsHitTesting(false)
                    .overlay {
                        Button {
                            showingPaywall = true
                        } label: {
                            Color.clear
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Requires Pro")
                        .accessibilityHint("Opens subscription options")
                    }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            SubscriptionView()
        }
    }
}

#Preview("Allowed") {
    PremiumGate(allowed: true) {
        Button("Premium Feature") {}
    }
}

#Preview("Blocked") {
    PremiumGate(allowed: false) {
        Button("Premium Feature") {}
    }
}
