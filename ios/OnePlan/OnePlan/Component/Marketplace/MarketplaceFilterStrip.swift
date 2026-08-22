//
//  MarketplaceFilterStrip.swift
//  OnePlan
//
//  Created by Codex on 20/4/26.
//

import SwiftUI

enum MarketplaceFilterChip: String, CaseIterable, Identifiable, Hashable {
    case duration
    case companions
    case budget

    var id: Self { self }

    var iconAssetName: String? {
        switch self {
        case .duration:
            "clockIcon"
        case .companions:
            "marketFriendIcon"
        case .budget:
            nil
        }
    }

    var iconSystemName: String? {
        switch self {
        case .budget:
            "dollarsign.circle.fill"
        case .duration, .companions:
            nil
        }
    }
}

enum MarketplaceDurationRange: String, CaseIterable, Identifiable {
    case oneToThree = "1-3 days"
    case fourToSeven = "4-7 days"
    case eightToFourteen = "8-14 days"

    var id: Self { self }

    /// Localized display label (rawValue stays English for identity/query).
    var localizedTitle: String {
        switch self {
        case .oneToThree: String(localized: "1-3 days")
        case .fourToSeven: String(localized: "4-7 days")
        case .eightToFourteen: String(localized: "8-14 days")
        }
    }
}

enum MarketplaceBudgetSort: String, CaseIterable, Identifiable {
    case ascending = "Ascending"
    case descending = "Descending"

    var localizedTitle: String {
        switch self {
        case .ascending: String(localized: "Ascending", comment: "Budget sort order")
        case .descending: String(localized: "Descending", comment: "Budget sort order")
        }
    }

    var id: Self { self }
}

struct MarketplaceFilterStrip: View {
    @Binding var selectedFilters: Set<MarketplaceFilterChip>
    @Binding var selectedDurationRange: MarketplaceDurationRange
    @Binding var selectedBudgetSort: MarketplaceBudgetSort?
    @Binding var selectedTag: Components.Schemas.ListingTag
    private let allTags: [Components.Schemas.ListingTag] = [
        .COMPANY, .COUPLES, .FAMILY, .FRIENDS, .SOLO,
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MarketplaceFilterChip.allCases) { filter in
                if filter == .duration {
                    Menu {
                        Button {
                            selectedFilters.remove(.duration)
                        } label: {
                            if !selectedFilters.contains(.duration) {
                                Label("None", systemImage: "checkmark")
                            } else {
                                Text("None")
                            }
                        }

                        ForEach(MarketplaceDurationRange.allCases) { range in
                            Button {
                                selectedDurationRange = range
                                selectedFilters.insert(.duration)
                            } label: {
                                if selectedFilters.contains(.duration),
                                   selectedDurationRange == range {
                                    Label(range.localizedTitle, systemImage: "checkmark")
                                } else {
                                    Text(range.localizedTitle)
                                }
                            }
                        }
                    } label: {
                        filterChipLabel(for: filter)
                    }
                    .fixedSize()
                } else if filter == .budget {
                    Menu {
                        Button {
                            selectedBudgetSort = nil
                            selectedFilters.remove(.budget)
                        } label: {
                            if selectedBudgetSort == nil {
                                Label("None", systemImage: "checkmark")
                            } else {
                                Text("None")
                            }
                        }

                        ForEach(MarketplaceBudgetSort.allCases) { sort in
                            Button {
                                selectedBudgetSort = sort
                                selectedFilters.insert(.budget)
                            } label: {
                                if selectedBudgetSort == sort {
                                    Label(sort.localizedTitle, systemImage: "checkmark")
                                } else {
                                    Text(sort.localizedTitle)
                                }
                            }
                        }
                    } label: {
                        filterChipLabel(for: filter)
                    }
                    .fixedSize()
                } else if filter == .companions {
                    Menu {
                        Button {
                            selectedFilters.remove(.companions)
                        } label: {
                            if !selectedFilters.contains(.companions) {
                                Label("None", systemImage: "checkmark")
                            } else {
                                Text("None")
                            }
                        }

                        ForEach(allTags, id: \.rawValue) { tag in
                            Button {
                                selectedTag = tag
                                selectedFilters.insert(.companions)
                            } label: {
                                if selectedFilters.contains(.companions),
                                   selectedTag == tag {
                                    Label(tag.pickerTitle, systemImage: "checkmark")
                                } else {
                                    Text(tag.pickerTitle)
                                }
                            }
                        }
                    } label: {
                        filterChipLabel(for: filter)
                    }
                    .fixedSize()
                } else {
                    Button {
                        toggle(filter)
                    } label: {
                        filterChipLabel(for: filter)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 1)
    }

    private func title(for filter: MarketplaceFilterChip) -> String {
        switch filter {
        case .duration:
            selectedFilters.contains(.duration) ? selectedDurationRange.localizedTitle : String(localized: "Duration")
        case .companions:
            selectedFilters.contains(.companions) ? selectedTag.pickerTitle : String(localized: "Companion")
        case .budget:
            selectedBudgetSort?.localizedTitle ?? String(localized: "Budget")
        }
    }

    private func filterChipLabel(for filter: MarketplaceFilterChip) -> some View {
        HStack(spacing: 3) {
            filterIcon(for: filter)

            Text(title(for: filter))
                .font(
                    Font.beVietnamPro(15, weight: .medium)
                )
                .foregroundStyle(
                    selectedFilters.contains(filter)
                        ? Constants.ContentB : Constants.ContentM
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Constants.Neutral100)
                .overlay {
                    Capsule()
                        .fill(Constants.White.opacity(0.92))
                        .padding(1)
                }
        }
    }

    @ViewBuilder
    private func filterIcon(for filter: MarketplaceFilterChip) -> some View {
        if let iconAssetName = filter.iconAssetName {
            Image(iconAssetName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 16, height: 16)
                .opacity(selectedFilters.contains(filter) ? 1 : 0.55)
        } else if let iconSystemName = filter.iconSystemName {
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    selectedFilters.contains(filter)
                        ? Constants.ContentB : Constants.ContentM
                )
                .frame(width: 16, height: 16)
                .opacity(selectedFilters.contains(filter) ? 1 : 0.55)
        }
    }

    private func toggle(_ filter: MarketplaceFilterChip) {
        if selectedFilters.contains(filter) {
            selectedFilters.remove(filter)
        } else {
            selectedFilters.insert(filter)
        }
    }
}

#Preview {
    StatefulMarketplaceFilterStripPreview()
        .padding()
        .background(Constants.Background)
}

private struct StatefulMarketplaceFilterStripPreview: View {
    @State private var selectedFilters: Set<MarketplaceFilterChip> = []
    @State private var selectedDurationRange: MarketplaceDurationRange = .oneToThree
    @State private var selectedBudgetSort: MarketplaceBudgetSort?
    @State private var selectedTag: Components.Schemas.ListingTag = .FRIENDS

    var body: some View {
        MarketplaceFilterStrip(
            selectedFilters: $selectedFilters,
            selectedDurationRange: $selectedDurationRange,
            selectedBudgetSort: $selectedBudgetSort,
            selectedTag: $selectedTag
        )
    }
}

extension Components.Schemas.ListingTag {
    fileprivate var pickerTitle: String {
        switch self {
        case .COMPANY:
            String(localized: "Company")
        case .COUPLES:
            String(localized: "Couples")
        case .FAMILY:
            String(localized: "Family")
        case .FRIENDS:
            String(localized: "Friends")
        case .SOLO:
            String(localized: "Solo")
        }
    }
}
