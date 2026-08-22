//
//  TripInviteView.swift
//  OnePlan
//

import CoreImage.CIFilterBuiltins
import SwiftUI

struct TripInviteView: View {
    let tripId: Int
    let tripName: String
    let coverImageUrl: String?
    let inviteCode: String
    let members: [TripMemberDto]

    @State private var friendService = FriendService()
    @State private var tripService = TripService()
    @State private var invitedFriendIds: Set<Int> = []
    @State private var invitingFriendIds: Set<Int> = []

    private var shareURL: URL {
        DeepLinkBuilder.tripURL(code: inviteCode)
    }

    private var deepLinkDisplay: String {
        shareURL.absoluteString
    }

    private var existingMemberIds: Set<Int> {
        Set(members.map(\.userId))
    }

    private var friendEntries: [FriendListEntry] {
        friendService.friends.map { friend in
            let userId = friend.user.id
            let isSent =
                existingMemberIds.contains(userId)
                || invitedFriendIds.contains(userId)
                || invitingFriendIds.contains(userId)
            return FriendListEntry(
                id: "\(userId)",
                name: friend.user.displayName,
                subtitleText: "\(friend.mutualFriendCount) mutual friends",
                avatarUrl: friend.user.avatarUrl,
                trailingAction: isSent ? .sent : .invite,
                isPro: friend.user.isPro
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inviteCard
                membersCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
        }
        .background(Constants.Background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await friendService.loadFriends()
        }
    }

    // MARK: - Invite Card

    private var inviteCard: some View {
        VStack(alignment: .center, spacing: 12) {
            tripInfoHeader
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    Rectangle()
                        .inset(by: 0.5)
                        .stroke(Constants.DividerStroke, lineWidth: 1)
                )

            StyledQRCodeView(
                content: deepLinkDisplay,
                color: Constants.BlueBase,
                size: 222
            )
            .padding(.vertical, 8)

            shareLinkRow
                .padding(.horizontal, 16)
        }
        .padding(.top, 0)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Constants.Surface)
        .cornerRadius(32)
    }

    // MARK: - Trip Info Header

    private var tripInfoHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            if let urlString = coverImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image("defaultTripPlaceholder")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
            } else {
                Image("defaultTripPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tripName)
                    .font(
                        Font.beVietnamPro(16, weight: .medium)
                    )
                    .foregroundColor(Constants.ContentB)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Text(
                    "Join the group and plan together by scanning the QR code below!"
                )
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Share Link Row

    private var shareLinkRow: some View {
        VStack {
            HStack(alignment: .center, spacing: 8) {
                Text(deepLinkDisplay)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundColor(Constants.ContentB)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                ShareLink(
                    item: shareURL,
                    subject: Text("Join \(tripName) on OnePlan")
                ) {
                    Chip(variant: .blue, text: String(localized: "Share"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Constants.OnSurface)
            .cornerRadius(20)
        }
    }

    // MARK: - Members Card

    private var membersCard: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("Friends · \(friendService.friends.count) friends")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            FriendList(
                entries: friendEntries,
                onTrailingActionTapped: { entry in
                    guard let userId = Int(entry.id) else { return }
                    Task {
                        await inviteFriend(userId: userId)
                    }
                },
                titleFontSize: 14,
                subtitleFontSize: 12,
                imageSize: 42,
                horizontalPadding: 0
            )

            if let error = tripService.error {
                Text(error)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.Warning500)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Constants.Surface)
        .cornerRadius(32)
    }

    @MainActor
    private func inviteFriend(userId: Int) async {
        guard !existingMemberIds.contains(userId) else { return }
        guard !invitingFriendIds.contains(userId) else { return }

        invitingFriendIds.insert(userId)
        defer {
            invitingFriendIds.remove(userId)
        }

        do {
            try await tripService.inviteMembers(
                tripId: tripId,
                userIds: [userId]
            )
            invitedFriendIds.insert(userId)
            tripService.error = nil
        } catch {
            // tripService.error is already set
        }
    }
}

#Preview {
    NavigationStack {
        TripInviteView(
            tripId: 1,
            tripName: "Dubai 2025",
            coverImageUrl: nil,
            inviteCode: "abc123def456",
            members: []
        )
    }
}
