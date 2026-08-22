import SwiftUI

struct LocationDetailTabBar: View {
    @Binding var selectedTab: LocationDetailTab

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ForEach(LocationDetailTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.localizedTitle)
                        .font(
                            selectedTab == tab
                                ? Font.beVietnamPro(16, weight: .medium)
                                : Font.custom("Be Vietnam Pro", size: 16)
                        )
                        .foregroundStyle(
                            selectedTab == tab
                                ? Constants.BlueBase : Constants.ContentL
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}

struct LocationDetailTabContent: View {
    let selectedTab: LocationDetailTab
    let topEntries: [LocationTopEntry]

    @ViewBuilder
    var body: some View {
        switch selectedTab {
        case .top:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(topEntries) { entry in
                    LocationTopEntryRow(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(minHeight: 272, alignment: .top)
        case .photo:
            VStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Constants.ContentL)

                Text("Photo content")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 272)
        }
    }
}

struct LocationTopEntryRow: View {
    let entry: LocationTopEntry

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image("defaultTripPlaceholder")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 3) {
                    Text(entry.name)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)

                    if entry.isFriend {
                        AppPill(
                            title: "Friends",
                            style: .compactBlue
                        )
                    }
                }

                Text(entry.mutualFriendsText)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.ranking)
                .font(.system(size: 40, weight: .heavy, design: .serif))
                .foregroundStyle(Constants.Neutral100)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private let locationDetailTabsPreviewEntries: [LocationTopEntry] = [
    LocationTopEntry(
        id: "jason",
        name: "Jason Kim",
        mutualFriendsText: "0 mutual friends",
        ranking: "12x",
        isFriend: false
    ),
    LocationTopEntry(
        id: "hmy",
        name: "hmy",
        mutualFriendsText: "4 mutual friends",
        ranking: "8x",
        isFriend: true
    ),
]

private struct LocationDetailTabBarPreviewContainer: View {
    @State private var selectedTab: LocationDetailTab = .top

    var body: some View {
        LocationDetailTabBar(selectedTab: $selectedTab)
            .padding(16)
            .background(Constants.Surface)
    }
}

#Preview("LocationDetailTabBar") {
    LocationDetailTabBarPreviewContainer()
}

#Preview("LocationDetailTabContent Top") {
    LocationDetailTabContent(
        selectedTab: .top,
        topEntries: locationDetailTabsPreviewEntries
    )
    .padding(16)
    .background(Constants.Surface)
}

#Preview("LocationDetailTabContent Photo") {
    LocationDetailTabContent(
        selectedTab: .photo,
        topEntries: locationDetailTabsPreviewEntries
    )
    .padding(16)
    .background(Constants.Surface)
}
