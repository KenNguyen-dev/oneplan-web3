//
//  FriendProfileView.swift
//  OnePlan
//
//  Created by ken on 6/4/26.
//

import SwiftUI
import UIKit

enum FriendProfileAction {
    case add
    case cancel
    case accept
    case decline
    case remove
}

struct FriendProfileView: View {
    let userId: Int
    var onDismiss: () -> Void = {}
    @State private var friendService = FriendService()
    @State private var isPerformingAction = false
    @State private var isShowingRemoveConfirm = false
    private let contentWidth: CGFloat = 369

    private var profile: FriendProfileDto? { friendService.profile }

    private var friendEntries: [FriendListEntry] {
        profile?.friends.map { friend in
            FriendListEntry(
                id: "\(friend.userId)",
                name: friend.displayName,
                subtitleText: String(localized: "\(friend.friendCount) friends (\(friend.mutualFriendCount) mutuals)", comment: "%1$lld = friend count, %2$lld = mutual count"),
                avatarUrl: friend.avatarUrl,
                isPro: friend.isPro
            )
        } ?? []
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Image("friendProfileHeaderBackground")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .top)
                    .accessibilityHidden(true)

                VStack(alignment: .center, spacing: 20) {
                    FriendProfileHeaderSection(
                        displayName: profile?.displayName ?? "",
                        avatarUrl: profile?.avatarUrl,
                        friendCode: profile?.friendCode,
                        requestStatus: profile?.requestStatus,
                        isPerformingAction: isPerformingAction,
                        isPro: profile?.isPro ?? false,
                        onAction: { action in
                            Task { await handleFriendAction(action) }
                        }
                    )

                    FriendProfileMetricsSection(
                        tripCount: profile?.tripCount ?? 0,
                        cityCount: profile?.cityCount ?? 0
                    )

                    FriendProfileFriendsSection(
                        friendCount: profile?.friendCount ?? 0,
                        entries: friendEntries
                    )
                }
                .frame(maxWidth: contentWidth)
                .padding(.horizontal, 12)
                .padding(.top, 46)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)

                FriendProfileToolbarMenu(
                    friendName: profile?.displayName ?? "",
                    friendCode: profile?.friendCode ?? "",
                    requestStatus: profile?.requestStatus,
                    isPerformingAction: isPerformingAction,
                    onRemove: {
                        isShowingRemoveConfirm = true
                    }
                )
                .padding(.top, 16)
                .padding(.leading, 16)
            }
        }
        .background(Constants.Background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            DismissButton(action: onDismiss)
        }
        .task {
            await friendService.loadUserProfile(userId: userId)
        }
        .alert("Remove friend?", isPresented: $isShowingRemoveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await handleFriendAction(.remove) }
            }
        } message: {
            Text(
                "\(profile?.displayName ?? "This person") will be removed from your friends list."
            )
        }
    }

    private func handleFriendAction(_ action: FriendProfileAction) async {
        guard !isPerformingAction, let profile else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            switch action {
            case .add:
                guard let friendCode = profile.friendCode else { return }
                try await friendService.sendRequest(friendCode: friendCode)
                await friendService.loadUserProfile(userId: userId)

            case .cancel:
                guard let friendCode = profile.friendCode else { return }
                try await friendService.cancelSentRequest(friendCode: friendCode)
                await friendService.loadUserProfile(userId: userId)

            case .accept:
                guard let requestId = profile.friendRequestId else { return }
                try await friendService.respondToRequest(id: requestId, accept: true)
                await friendService.loadUserProfile(userId: userId)

            case .decline:
                guard let requestId = profile.friendRequestId else { return }
                try await friendService.respondToRequest(id: requestId, accept: false)
                await friendService.loadUserProfile(userId: userId)

            case .remove:
                guard let friendshipId = profile.friendshipId else { return }
                try await friendService.unfriend(friendshipId: friendshipId)
                NotificationCenter.default.post(
                    name: .friendRemoved,
                    object: nil
                )
                onDismiss()
            }
        } catch {
            print("FriendProfileView action failed: \(error)")
        }
    }
}

private struct FriendProfileToolbarMenu: View {
    let friendName: String
    let friendCode: String
    let requestStatus: FriendProfileDto.requestStatusPayload?
    let isPerformingAction: Bool
    let onRemove: () -> Void

    var body: some View {
        Menu {
//            ShareLink(item: "\(friendName) (\(friendCode))") {
//                Label(
//                    "Share",
//                    systemImage: "point.3.connected.trianglepath.dotted"
//                )
//            }

            if requestStatus == .friends {
                // Below iOS 26 menu dividers render as ugly thick gray bands;
                // show only on iOS 26+ where the separator is refined.
                if #available(iOS 26.0, *) {
                    Divider()
                }

                Button(role: .destructive, action: onRemove) {
                    Label("Remove friend", systemImage: "hand.wave.fill")
                }
                .disabled(isPerformingAction)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .glassEffectCompat()

        }
    }
}

private struct FriendProfileHeaderSection: View {
    let displayName: String
    let avatarUrl: String?
    let friendCode: String?
    let requestStatus: FriendProfileDto.requestStatusPayload?
    let isPerformingAction: Bool
    let isPro: Bool
    let onAction: (FriendProfileAction) -> Void

    var body: some View {
        VStack(spacing: 19) {
            AvatarProPlaceholder(
                size: 81,
                imageUrl: avatarUrl,
                showBadge: isPro
            )

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(Font.custom("Be Vietnam Pro", size: 28))
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)

                    if isPro {
                        FriendProfilePillBadge(text: String(localized: "Pro"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Text("OP-2006-2710")
                    .font(
                        .system(
                            size: 12,
                            weight: .regular,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(Constants.ContentM)
                    .tracking(0.6)
            }

            if let requestStatus {
                actionArea(for: requestStatus)
            }
        }
    }

    @ViewBuilder
    private func actionArea(for status: FriendProfileDto.requestStatusPayload) -> some View {
        switch status {
        case .none:
            
            AddFriendButton(title: "Add friend") {
                onAction(.add)
            }
            .frame(width: 140)
            .disabled(isPerformingAction)

        case .pending_sent:
            AddFriendButton(title: "Cancel request") {
                onAction(.cancel)
            }
            .frame(width: 180)
            .disabled(isPerformingAction)

        case .pending_received:
            HStack(spacing: 12) {
                AddFriendButton(title: "Accept") {
                    onAction(.accept)
                }
                SecondaryButton(title: "Decline", variant: .light) {
                    onAction(.decline)
                }
            }
            .frame(maxWidth: 300)
            .disabled(isPerformingAction)

        case .friends:
            EmptyView()
        }
    }
}

private struct FriendProfilePillBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Font.custom("Be Vietnam Pro", size: 13))
            .tracking(-0.52)
            .foregroundStyle(Constants.BlueBase)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Constants.BlueBase, lineWidth: 1)
            }
    }
}

private struct FriendProfileMetricsSection: View {
    let tripCount: Int
    let cityCount: Int

    var body: some View {
        HStack(spacing: 8) {
            FriendProfileMetricCard(
                title: String(localized: "Trips"),
                value: String(format: "%02d", tripCount)
            )

            FriendProfileMetricCard(
                title: String(localized: "Cities"),
                value: String(format: "%02d", cityCount)
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FriendProfileMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(Font.beVietnamPro(32, weight: .semibold))
                .foregroundStyle(Constants.Neutral900)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .tracking(-0.42)
                .foregroundStyle(Constants.Neutral900)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Constants.White.opacity(0.86))
                .shadow(
                    color: Constants.Black.opacity(0.14),
                    radius: 16,
                    x: 0,
                    y: 0
                )
        }
    }
}

private struct FriendProfileFriendsSection: View {
    let friendCount: Int
    let entries: [FriendListEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(friendCount) friends")
                .font(Font.beVietnamPro(16, weight: .medium))
                .tracking(-0.64)
                .foregroundStyle(Constants.ContentM)

            FriendList(entries: entries)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        FriendProfileView(userId: 1)
    }
}
