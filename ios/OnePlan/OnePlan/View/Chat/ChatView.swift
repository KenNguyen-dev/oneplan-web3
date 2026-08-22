//
//  ChatView.swift
//  OnePlan
//
//  Created by ken on 26/2/26.
//

import SwiftUI

struct ChatView: View {
    @Environment(RealtimeService.self) private var realtimeService
    @Environment(UserProfileService.self) private var userProfileService
    let tripService: TripService
    @Binding var deepLinkChatTripId: Int?
    @State private var selectedEntry: ChatListEntry?
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    private let friends: [String] = ["Carlos", "Huy", "Hyy", "Alan", "JP"]

    private var allTrips: [TripSummaryDto] {
        tripService.ongoingTrips + tripService.planningTrips
    }

    private var chatEntries: [ChatListEntry] {
        allTrips.map { trip in
            let latestMessageText =
                realtimeService.previewText(for: trip.id)
                ?? "Tap to start chatting"

            return ChatListEntry(
                tripId: trip.id,
                name: trip.name,
                coverImageUrl: trip.coverImageUrl,
                latestMessageId: realtimeService.threadSummaries[trip.id]?
                    .latestMessage?.id,
                message: latestMessageText,
                dateText: realtimeService.previewDateText(for: trip.id),
                imageNames: [],
                hasStatusDot: realtimeService.isTripUnread(
                    tripId: trip.id,
                    serverSeenMessageId: trip.lastSeenChatMessageId,
                    currentUserId: userProfileService.profile?.id
                ),
                extraMemberCount: trip.memberCount > 2
                    ? trip.memberCount - 2 : nil
            )
        }
    }

    private var filteredChatEntries: [ChatListEntry] {
        let terms = normalizedSearchTerms
        guard !terms.isEmpty else { return chatEntries }
        return chatEntries.filter { entry in
            let searchableText = normalizedSearchText(
                [entry.name, entry.message, entry.dateText].joined(
                    separator: " "
                )
            )
            return terms.allSatisfy {
                searchableText.localizedStandardContains($0)
            }
        }
    }

    private var normalizedSearchTerms: [String] {
        normalizedSearchText(searchText)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private var isSearching: Bool {
        !normalizedSearchTerms.isEmpty
    }

    init(
        tripService: TripService,
        deepLinkChatTripId: Binding<Int?> = .constant(nil)
    ) {
        self.tripService = tripService
        self._deepLinkChatTripId = deepLinkChatTripId
    }

    var body: some View {
        AppScreenContainer {
            ScrollView {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 16) {
                        SearchBar(
                            text: $searchText,
                            placeholder: "Search trips",
                            focused: $isSearchFocused
                        )

                        //                        Text("Friends")
                        //                            .font(
                        //                                Font.custom("Be Vietnam Pro", size: 16)
                        //                                    .weight(.medium)
                        //                            )
                        //                            .foregroundColor(Constants.ContentM)
                        //                            .frame(maxWidt    h: .infinity, alignment: .topLeading)
                    }
                    .padding(.horizontal, 16)

                    //                    ScrollView(.horizontal, showsIndicators: false) {
                    //                        HStack(alignment: .top, spacing: 14) {
                    //                            ForEach(friends, id: \.self) { friend in
                    //                                FriendImageHolder(name: friend, imageName: "defaultTripPlaceholder")
                    //                            }
                    //                        }
                    //                    }
                    //                    .padding(.leading, 12)

                    if filteredChatEntries.isEmpty {
                        Group {
                            if isSearching {
                                EmptyChatSearchResults {
                                    searchText = ""
                                    isSearchFocused = true
                                }
                            } else {
                                EmptyChat()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 340)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    } else {
                        ChatList(entries: filteredChatEntries) { entry in
                            selectedEntry = entry
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task {
            await refreshChatEntries()
            if let deepLinkChatTripId {
                await routeToChatTrip(tripId: deepLinkChatTripId)
            }
        }
        .onAppear {
            Task {
                await refreshChatEntries()
            }
        }
        .onChange(of: deepLinkChatTripId) { _, newValue in
            guard let newValue else { return }
            Task {
                await routeToChatTrip(tripId: newValue)
            }
        }
        .navigationDestination(item: $selectedEntry) { entry in
            ChatDetailView(
                tripId: entry.tripId,
                tripName: entry.name,
                coverImageUrl: entry.coverImageUrl
            )
        }
    }

    @MainActor
    private func routeToChatTrip(tripId: Int) async {
        if let entry = chatEntries.first(where: { $0.tripId == tripId }) {
            if selectedEntry?.tripId != entry.tripId {
                selectedEntry = entry
            }
            deepLinkChatTripId = nil
            return
        }

        await refreshChatEntries(force: true)
        if let entry = chatEntries.first(where: { $0.tripId == tripId }) {
            if selectedEntry?.tripId != entry.tripId {
                selectedEntry = entry
            }
        } else {
            selectedEntry = nil
        }

        // Fallback behavior: stay on chat list if trip is unavailable
        deepLinkChatTripId = nil
    }

    @MainActor
    private func refreshChatEntries(force: Bool = false) async {
        await tripService.listMyTrips(force: force)
        realtimeService.syncTripSeenState(from: allTrips)
        await realtimeService.loadThreadSummaries(
            tripIds: allTrips.map(\.id),
            force: force
        )
    }

    private func normalizedSearchText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }
}

private struct EmptyChatSearchResults: View {
    let clearSearch: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            Image("emptyChat")
                .resizable()
                .scaledToFit()
                .frame(width: 165.449, height: 165.449)

            Text("No matching chats.")
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .tracking(-0.64)
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentM)

            Button("Clear search") {
                clearSearch()
            }
            .font(
                Font.beVietnamPro(14, weight: .medium)
            )
            .foregroundColor(Constants.BlueBase)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

#Preview {
    ChatView(tripService: TripService(), deepLinkChatTripId: .constant(nil))
        .background(Constants.Background.ignoresSafeArea())
}
