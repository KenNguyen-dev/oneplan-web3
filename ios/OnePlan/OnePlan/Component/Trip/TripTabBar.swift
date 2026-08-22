//
//  TripTabBar.swift
//  OnePlan
//
//  Created by Codex on 26/2/26.
//

import SwiftUI

enum TripTab: String, CaseIterable, Identifiable {
    case history = "History"
    case yourPlan = "Your plan"
    case note = "Note"
    // case photo = "Photo"
    case members = "Members"
    case insight = "Insight"

    var id: String { rawValue }

    /// Localized tab title (rawValue stays English for identity/logic).
    var localizedTitle: String {
        switch self {
        case .history: String(localized: "History", comment: "Trip tab: expense/budget history")
        case .yourPlan: String(localized: "Your plan", comment: "Trip tab: the trip's plan")
        case .note: String(localized: "Note", comment: "Trip tab: trip notes")
        case .members: String(localized: "Members", comment: "Trip tab: members")
        case .insight: String(localized: "Insight", comment: "Trip tab: spending insights")
        }
    }
}

struct TripTabBar: View {
    @Binding var selectedTab: TripTab
    let isEnabled: Bool
    @State private var tappedTab: TripTab?

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(TripTab.allCases, id: \.id) { tab in
                Button {
                    guard isEnabled, selectedTab != tab else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    tappedTab = tab
                    withAnimation(.snappy(duration: 0.25)) {
                        selectedTab = tab
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        tappedTab = nil
                    }
                } label: {
                    Text(tab.localizedTitle)
                        .font(tabFont(for: tab))
                        .lineSpacing(0)
                        .tracking(-0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(tabTitleColor(for: tab))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(tabBackgroundColor(for: tab))
                        )
                        .scaleEffect(tappedTab == tab ? 1.08 : 1.0)
                        .animation(.spring(duration: 0.3, bounce: 0.4), value: tappedTab)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        .animation(.snappy(duration: 0.25), value: selectedTab)
        .opacity(isEnabled ? 1 : 0.5)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabFont(for tab: TripTab) -> Font {
        if selectedTab == tab {
            return Font.beVietnamPro(15, weight: .medium)
        } else {
            return Font.custom("Be Vietnam Pro", size: 15)
        }
    }

    private func tabTitleColor(for tab: TripTab) -> Color {
        isEnabled && selectedTab == tab ? Constants.BlueBase : Constants.ContentL
    }

    private func tabBackgroundColor(for tab: TripTab) -> Color {
        isEnabled && selectedTab == tab ? Constants.BlueAlpha10 : .clear
    }
}

#Preview {
    TripTabBar(selectedTab: .constant(.history), isEnabled: true)
        .padding()
}
