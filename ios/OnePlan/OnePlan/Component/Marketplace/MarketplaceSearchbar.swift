//
//  MarketplaceSearchbar.swift
//  OnePlan
//
//  Created by Codex on 26/3/26.
//

import SwiftUI

enum MarketplaceDiscoveryTab: String, CaseIterable, Identifiable {
    case trending = "Trending"
    case topRated = "Top Rated"

    var id: Self { self }

    /// Localized display label (rawValue stays English for identity).
    var localizedTitle: String {
        switch self {
        case .trending: String(localized: "Trending", comment: "Marketplace discovery tab")
        case .topRated: String(localized: "Top Rated", comment: "Marketplace discovery tab")
        }
    }

    var iconAssetName: String {
        switch self {
        case .trending:
            "fireTrendingIcon"
        case .topRated:
            "goldenStarIcon"
        }
    }
}

struct MarketplaceSearchbar: View {
    
    private static let placeholderCities = [
        "London", "Tokyo", "Paris", "New York", "Singapore", "Seoul",
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var placeholderCity =
        MarketplaceSearchbar.placeholderCities.randomElement() ?? "London"

    var selectedDestinationText: String? = nil
    var selectedTab: MarketplaceDiscoveryTab = .trending
    var onSearchTap: () -> Void = {}
    var onClearTap: () -> Void = {}
    var onTabSelected: (MarketplaceDiscoveryTab) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    onSearchTap()
                } label: {
                    HStack(spacing: 8) {
                        Image("locationSearchIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)

                        destinationLabel

                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                if showsClearButton {
                    Button {
                        onClearTap()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Constants.ContentB)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Constants.White)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.09), radius: 17.9, x: 0, y: 0)

            HStack(spacing: 27) {
                ForEach(MarketplaceDiscoveryTab.allCases) { tab in
                    Button {
                        onTabSelected(tab)
                    } label: {
                        VStack(spacing: 11) {
                            HStack(spacing: 6) {
                                Image(tab.iconAssetName)
                                    .resizable()
                                    .renderingMode(.original)
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)

                                Text(tab.localizedTitle)
                                    .font(
                                        Font.beVietnamPro(15, weight: .medium)
                                    )
                                    .foregroundStyle(Constants.ContentB)
                                    .tracking(-0.15)
                            }
                            .frame(maxWidth: .infinity)

                            Rectangle()
                                .fill(
                                    selectedTab == tab
                                        ? Constants.BlueBase : .clear
                                )
                                .frame(width: 32, height: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: shouldAnimatePlaceholder) {
            guard shouldAnimatePlaceholder else { return }
            await animatePlaceholderLoop()
        }
    }

    private var normalizedDestinationText: String? {
        let text = selectedDestinationText?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private var showsClearButton: Bool {
        normalizedDestinationText != nil
    }

    private var shouldAnimatePlaceholder: Bool {
        normalizedDestinationText == nil
    }

    private var destinationLabel: some View {
        ZStack(alignment: .leading) {
            if let normalizedDestinationText {
                Text(normalizedDestinationText)
                    .id("selected-\(normalizedDestinationText)")
                    .foregroundStyle(Constants.ContentB)
                    .transition(.opacity)
            } else {
                Text(placeholderCity)
                    .id("placeholder-\(placeholderCity)")
                    .foregroundStyle(Constants.ContentL)
                    .transition(placeholderTransition)
            }
        }
        .font(Font.custom("Be Vietnam Pro", size: 15))
        .tracking(-0.3)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(animationStyle, value: normalizedDestinationText)
        .animation(animationStyle, value: placeholderCity)
    }

    private var animationStyle: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)
    }

    private var placeholderTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .offset(y: 6).combined(with: .opacity),
                removal: .offset(y: -6).combined(with: .opacity)
            )
    }

    private func animatePlaceholderLoop() async {
        while !Task.isCancelled && shouldAnimatePlaceholder {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled && shouldAnimatePlaceholder else { break }

            let nextCity = nextPlaceholderCity()
            await MainActor.run {
                withAnimation(animationStyle) {
                    placeholderCity = nextCity
                }
            }
        }
    }

    private func nextPlaceholderCity() -> String {
        let candidates = Self.placeholderCities.filter { $0 != placeholderCity }
        return candidates.randomElement() ?? placeholderCity
    }
}

#Preview {
    StatefulMarketplaceSearchbarPreview()
}

private struct StatefulMarketplaceSearchbarPreview: View {
    @State private var selectedTab: MarketplaceDiscoveryTab = .trending
    @State private var selectedDestinationText: String?

    var body: some View {
        MarketplaceSearchbar(
            selectedDestinationText: selectedDestinationText,
            selectedTab: selectedTab,
            onSearchTap: {
                selectedDestinationText = "Tokyo"
            },
            onClearTap: {
                selectedDestinationText = nil
            },
            onTabSelected: { selectedTab = $0 }
        )
        .padding()
        .background(Constants.Background)
    }
}
