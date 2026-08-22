//
//  FriendsListView.swift
//  OnePlan
//

import SwiftUI

extension FriendRequestDto: Identifiable {}

struct FriendsListView: View {
    @State private var friendService = FriendService()
    @State private var selectedRequest: FriendRequestDto?
    @State private var selectedFriendUserId: String?
    @Binding private var selectedFriendIds: Set<Int>
    private let showsInviteAction: Bool

    init(selectedFriendIds: Binding<Set<Int>>? = nil) {
        if let selectedFriendIds {
            self._selectedFriendIds = selectedFriendIds
            self.showsInviteAction = true
        } else {
            self._selectedFriendIds = .constant([])
            self.showsInviteAction = false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !friendService.pendingRequests.isEmpty {
                    pendingRequestsSection
                }

                friendsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .refreshable {
            await loadAllData()
        }
        .background(Constants.Background.ignoresSafeArea())
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAllData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .friendRemoved)) { _ in
            Task { await friendService.loadFriends() }
        }
        .fullScreenCover(item: $selectedRequest) { request in
            ReceiveFriendRequestView(
                requestId: request.id,
                senderName: request.sender.displayName,
                senderAvatarUrl: request.sender.avatarUrl,
                mutualFriendCount: request.mutualFriendCount,
                onAccept: {
                    Task {
                        try? await friendService.respondToRequest(id: request.id, accept: true)
                    }
                    selectedRequest = nil
                },
                onDismiss: {
                    selectedRequest = nil
                }
            )
        }
        .sheet(item: $selectedFriendUserId.identifiable) { wrapper in
            if let userId = Int(wrapper.value) {
                FriendProfileView(
                    userId: userId,
                    onDismiss: { selectedFriendUserId = nil }
                )
            }
        }
    }

    // MARK: - Pending Requests Section

    private var pendingRequestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pending Requests")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)

            VStack(spacing: 0) {
                ForEach(friendService.pendingRequests, id: \.id) { request in
                    Button {
                        selectedRequest = request
                    } label: {
                        pendingRequestRow(request)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Constants.Surface)
            .clipShape(.rect(cornerRadius: 24))
        }
    }

    private func pendingRequestRow(_ request: FriendRequestDto) -> some View {
        let avatarSize: CGFloat = 42

        return HStack(spacing: 12) {
            CachedRemoteImage(
                url: request.sender.avatarUrl.flatMap { URL(string: $0) },
                targetSize: CGSize(width: avatarSize, height: avatarSize)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image("avatarPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(request.sender.displayName)
                    .font(Font.beVietnamPro(14, weight: .medium))
                    .foregroundStyle(Constants.ContentB)
                    .lineLimit(1)

                Text("\(request.mutualFriendCount) mutual friends")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Friends Section

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if friendService.isLoadingFriends && friendService.friends.isEmpty {
                loadingState
            } else if friendService.friends.isEmpty {
                emptyState
            } else {
                FriendList(
                    entries: friendService.friends.map { friend in
                        let userId = friend.user.id
                        return FriendListEntry(
                            id: "\(userId)",
                            name: friend.user.displayName,
                            subtitleText: String(localized: "\(friend.mutualFriendCount) mutual friends"),
                            avatarUrl: friend.user.avatarUrl,
                            trailingAction: showsInviteAction
                                ? (selectedFriendIds.contains(userId) ? .sent : .invite)
                                : nil,
                            isPro: friend.user.isPro
                        )
                    },
                    onItemTapped: { entry in
                        selectedFriendUserId = entry.id
                    },
                    onTrailingActionTapped: showsInviteAction
                        ? { entry in
                            guard let userId = Int(entry.id) else { return }
                            selectedFriendIds.insert(userId)
                        }
                        : nil,
                    titleFontSize: 14,
                    subtitleFontSize: 12,
                    imageSize: 42,
                    horizontalPadding: 14
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 32))
                .foregroundStyle(Constants.ContentL)

            Text("No friends yet")
                .font(Font.beVietnamPro(16, weight: .medium))
                .foregroundStyle(Constants.ContentB)

            Text("Share your QR code or friend code to connect with others")
                .font(Font.custom("Be Vietnam Pro", size: 13))
                .foregroundStyle(Constants.ContentM)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Constants.Surface)
        .clipShape(.rect(cornerRadius: 24))
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack {
            ProgressView()
                .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity)
        .background(Constants.Surface)
        .clipShape(.rect(cornerRadius: 24))
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        async let friendsTask: () = friendService.loadFriends()
        async let requestsTask: () = friendService.loadPendingRequests()
        _ = await (friendsTask, requestsTask)
    }
}

#Preview {
    NavigationStack {
        FriendsListView()
    }
}
