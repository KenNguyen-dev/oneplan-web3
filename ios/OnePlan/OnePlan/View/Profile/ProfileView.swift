//
//  ProfileView.swift
//  OnePlan
//
//  Created by ken on 25/3/26.
//

import PhotosUI
import UIKit
import SwiftUI

struct ProfileView: View {
    /// When true, push the personal wallet detail as soon as Profile appears
    /// (welcome "Add money" deep link).
    var openWalletOnAppear: Bool = false
    /// When true with `openWalletOnAppear`, also present the deposit sheet.
    var openDepositOnAppear: Bool = false

    @Environment(UserProfileService.self) private var userProfileService
    @Environment(PassportService.self) private var passportService
    @Environment(RealtimeService.self) private var realtimeService
    @Environment(StoreManager.self) private var storeManager
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var navigateToQRScanner = false
    @State private var navigateToWallet = false
    @State private var navigateToSettings = false
    @State private var navigateToPassport = false
    @State private var navigateToCommunityProfile = false
    @State private var isShowingSubscription = false
    @State private var friendService = FriendService()
    @State private var walletBalanceMicro: UInt64 = 0
    @State private var isWalletLoading = true
    @State private var isShowingWalletDeposit = false
    @State private var isShowingWalletWithdraw = false
    @State private var walletOpenDepositOnAppear = false
    /// One-shot: welcome deep link must not re-fire when popping back to Profile.
    @State private var didConsumeOpenWalletIntent = false

    private static let indicativeUsdcToVnd: Double = 26_500

    private var walletBalanceUsdc: Double { Double(walletBalanceMicro) / 1_000_000 }

    var body: some View {
        let profile = userProfileService.profile

        ScrollView {
            ProfileAvatar(
                avatarUrl: profile?.avatarUrl,
                isUploading: userProfileService.isUploadingAvatar,
                isPro: storeManager.isPro
            ) { image in
                Task {
                    await userProfileService.uploadAvatar(image)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                OnePlanWalletCard(
                    email: profile?.email ?? "",
                    balanceUsdc: walletBalanceUsdc,
                    balanceVnd: walletBalanceUsdc * Self.indicativeUsdcToVnd,
                    isLoading: isWalletLoading,
                    onOpenDetail: {
                        walletOpenDepositOnAppear = false
                        navigateToWallet = true
                    },
                    onWithdraw: { isShowingWalletWithdraw = true },
                    onDeposit: { isShowingWalletDeposit = true }
                )
                .padding(.horizontal, 12)
                .zIndex(2)

                ProfileInfoCard(
                    profile: profile,
                    onCustomQRTap: {
                        navigateToQRScanner = true
                    },
                    onGetProTap: {
                        isShowingSubscription = true
                    }
                )
                    .padding(.horizontal, 12)
                    .zIndex(2)

                PassportSectionCard(
                    summary: passportService.summary,
                    fallbackDisplayName: profile?.displayName ?? String(localized: "One Plan User"),
                    onPassportTap: {
                        navigateToPassport = true
                    }
                )
                .padding(.horizontal, 12)
                .zIndex(0)

                CommunityProfileRow {
                    navigateToCommunityProfile = true
                }
                    .padding(.horizontal, 12)
                    .zIndex(3)

                NavigationLink {
                    FriendsListView()
                } label: {
                    ProfileFriendsSection(
                        friends: friendService.friends,
                        pendingRequests: friendService.pendingRequests
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .zIndex(3)
            }
            .padding(0)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .background(Constants.Background)
        .task { await userProfileService.fetchProfile() }
        .task { await passportService.fetchSummary() }
        .task { await friendService.loadFriends() }
        .task { await friendService.loadPendingRequests() }
        .task { await loadWalletBalance() }
        .task(id: openWalletOnAppear) {
            guard openWalletOnAppear, !didConsumeOpenWalletIntent else { return }
            didConsumeOpenWalletIntent = true
            walletOpenDepositOnAppear = openDepositOnAppear
            // Let Profile finish mounting before pushing wallet.
            try? await Task.sleep(for: .milliseconds(300))
            navigateToWallet = true
        }
        .onChange(of: networkMonitor.isOnline) { wasOnline, isOnline in
            // Came back online → refresh this view's local friend lists.
            // (Profile + passport are shared services refreshed app-level in
            // OnePlanApp; .task does not re-run on reconnect.)
            guard !wasOnline, isOnline else { return }
            Task { await friendService.loadFriends() }
            Task { await friendService.loadPendingRequests() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .friendRemoved)) { _ in
            Task { await friendService.loadFriends() }
        }
        .onChange(of: realtimeService.latestFriendRequest?.id) { _, _ in
            Task { await friendService.loadPendingRequests() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                HStack(spacing: -4) {
                    ToolbarIconButton(
                        systemName: "gearshape.fill",
                        horizontalPadding: 10,
                        verticalPadding: 10
                    ) {
                        navigateToSettings = true
                    }

                    ToolbarIconButton(
                        systemName: "qrcode.viewfinder",
                        horizontalPadding: 10,
                        verticalPadding: 10
                    ) {
                        navigateToQRScanner = true
                    }
                }
            }
            .sharedBackgroundHiddenCompat()
        }
        .navigationDestination(isPresented: $navigateToQRScanner) {
            // Routing uses `UIApplication.shared.open` rather than the SwiftUI
            // `@Environment(\.openURL)` action ON PURPOSE. Below iOS 26, the
            // `openURL` action gets a fresh identity on every NavigationStack
            // relayout; if a *pushed* destination (like ProfileView) reads it
            // and also hosts an onward push (this InviteView), the dependency
            // creates an infinite update loop that hangs the main thread. Both
            // route custom-scheme URLs to `OnePlanApp.onOpenURL` identically.
            InviteView { payload in
                let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                // Custom scheme — route via onOpenURL.
                if let url = URL(string: trimmed),
                   url.scheme?.lowercased() == DeepLinkBuilder.customScheme {
                    navigateToQRScanner = false
                    UIApplication.shared.open(url)
                    return
                }

                // Trip invite (HTTPS landing or raw code fallback).
                if let code = parseInviteCode(from: trimmed),
                   let inviteURL = DeepLinkBuilder.customSchemeJoin(code: code) {
                    navigateToQRScanner = false
                    UIApplication.shared.open(inviteURL)
                    return
                }

                // Friend invite (HTTPS landing).
                if let code = parseFriendCode(from: trimmed),
                   let friendURL = DeepLinkBuilder.customSchemeFriend(code: code) {
                    navigateToQRScanner = false
                    UIApplication.shared.open(friendURL)
                }
            }
        }
        .navigationDestination(isPresented: $navigateToWallet) {
            OnePlanWalletView(openDepositOnAppear: walletOpenDepositOnAppear)
        }
        .navigationDestination(isPresented: $navigateToSettings) {
            SettingView()
        }
        .sheet(isPresented: $isShowingWalletWithdraw, onDismiss: {
            Task { await loadWalletBalance() }
        }) {
            WalletWithdrawView {
                isShowingWalletWithdraw = false
            }
            .presentationDetents([.large])
            .presentationCornerRadius(48)
        }
        .sheet(isPresented: $isShowingWalletDeposit, onDismiss: {
            Task { await loadWalletBalance() }
        }) {
            DepositToOnePlanWalletView {
                isShowingWalletDeposit = false
            }
            .presentationDetents([.fraction(0.8)])
            .presentationCornerRadius(48)
        }
        .navigationDestination(isPresented: $navigateToPassport) {
            PassportView()
        }
        .navigationDestination(isPresented: $navigateToCommunityProfile) {
            MarketProfileOwnerView()
        }
        .fullScreenCover(isPresented: $isShowingSubscription) {
            SubscriptionView()
                .interactiveDismissDisabled(false)
        }
    }

    private func loadWalletBalance() async {
        isWalletLoading = true
        defer { isWalletLoading = false }
        do {
            let info = try await WalletWithdrawService.shared.myWallet()
            walletBalanceMicro = UInt64(info.balanceMicro) ?? 0
        } catch {
            // Profile still renders; balance stays at zero until retry.
            print("ProfileView.loadWalletBalance: \(error)")
        }
    }

    private func parseInviteCode(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let url = URL(string: trimmed) else { return trimmed }

        if url.scheme == nil, url.host == nil {
            return trimmed
        }

        if url.scheme?.lowercased() == DeepLinkBuilder.customScheme,
           url.host?.lowercased() == DeepLinkBuilder.joinPath {
            let code = url.pathComponents.dropFirst().first
            guard let code, !code.isEmpty else { return nil }
            return code
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let inviteCode = components.queryItems?.first(where: {
               $0.name.lowercased() == "invitecode" || $0.name.lowercased() == "code"
           })?.value,
           !inviteCode.isEmpty
        {
            return inviteCode
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if let joinIndex = pathComponents.firstIndex(where: {
            $0.lowercased() == DeepLinkBuilder.joinPath
        }),
           pathComponents.indices.contains(joinIndex + 1)
        {
            return pathComponents[joinIndex + 1]
        }

        return nil
    }

    private func parseFriendCode(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }

        if url.scheme?.lowercased() == DeepLinkBuilder.customScheme,
           url.host?.lowercased() == DeepLinkBuilder.friendPath,
           let code = url.pathComponents.dropFirst().first,
           !code.isEmpty {
            return code
        }

        if let host = url.host?.lowercased(),
           DeepLinkBuilder.universalLinkHosts.contains(host) {
            let segments = url.pathComponents.filter { $0 != "/" }
            if segments.first?.lowercased() == DeepLinkBuilder.friendPath,
               let code = segments.dropFirst().first,
               !code.isEmpty {
                return code
            }
        }

        return nil
    }
}

private struct ProfileAvatar: View {
    let avatarUrl: String?
    let isUploading: Bool
    let isPro: Bool
    let onImageSelected: (UIImage) -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?

    private let avatarSize: CGFloat = 155

    var body: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            ZStack {
                AvatarProPlaceholder(
                    size: avatarSize,
                    imageUrl: avatarUrl,
                    showBadge: isPro
                )

                if isUploading {
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: avatarSize, height: avatarSize)
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    onImageSelected(uiImage)
                }
            }
        }
    }
}

private struct ProfileInfoCard: View {
    let profile: UserProfileDto?
    let onCustomQRTap: () -> Void
    let onGetProTap: () -> Void

    @Environment(StoreManager.self) private var storeManager

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile?.displayName ?? String(localized: "One Plan User"))
                        .font(Font.custom("Be Vietnam Pro", size: 18))
                        .foregroundStyle(Constants.ContentB)

                    Text("OP-2006-2710")
                        .font(
                            .system(
                                size: 10,
                                weight: .regular,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(Constants.ContentM)
                        .tracking(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onCustomQRTap) {
                    Group {
                        if let friendCode = profile?.friendCode {
                            StyledQRCodeView(
                                content: DeepLinkBuilder.friendURL(code: friendCode).absoluteString,
                                color: Constants.BlueBase,
                                size: 64
                            )
                        } else {
                            Image(systemName: "qrcode")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                                .foregroundStyle(Constants.BlueBase)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            profileDivider

            HStack(spacing: 6) {
                Text("Email")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(profile?.email ?? "abc@gmail.com")
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-0.64)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)

            profileDivider

            HStack(spacing: 6) {
                Text("Subscription")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if storeManager.isPro {
                    ProBadge()
                } else {
                    Text("Basic")
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-0.64)

                    Button(action: onGetProTap) {
                        Text("Get Pro")
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundStyle(Constants.White)
                            .tracking(-0.6)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Constants.BlueBase)
                            .clipShape(Capsule())
                            .frame(minWidth: 65)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .padding(4)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 17.9, x: 0, y: 0)
    }

    private var profileDivider: some View {
        Rectangle()
            .fill(Constants.Neutral100)
            .frame(height: 1)
    }
}

private struct PassportSectionCard: View {
    let summary: PassportSummaryDto?
    let fallbackDisplayName: String
    let onPassportTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Passport")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentB)
                .tracking(-0.7)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 2)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.91, green: 0.95, blue: 0.99),
                        Color(red: 0.47, green: 0.73, blue: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .zIndex(0)

                PassportCard(
                    summary: summary,
                    fallbackDisplayName: fallbackDisplayName,
                    variant: .compact
                )
                .padding(.horizontal, 20)
                .padding(.top, 48)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .zIndex(1)
            }
            .frame(height: 132)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottom) {
                Button(action: onPassportTap) {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct CommunityProfileRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text("Community profile")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentB)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Constants.ContentM)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Constants.Surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileFriendsSection: View {
    let friends: [FriendDto]
    let pendingRequests: [FriendRequestDto]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pending requests section
            if !pendingRequests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Friend requests")
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundStyle(Constants.ContentM)
                            .tracking(-0.6)

                        Text("\(pendingRequests.count)")
                            .font(Font.beVietnamPro(12, weight: .medium))
                            .foregroundStyle(Constants.White)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Constants.BlueBase)
                            .clipShape(Capsule())

                        Spacer()
                    }

                    FriendList(
                        entries: pendingRequests.map { request in
                            FriendListEntry(
                                id: "request-\(request.id)",
                                name: request.sender.displayName,
                                subtitleText: String(localized: "\(request.mutualFriendCount) mutual friends"),
                                avatarUrl: request.sender.avatarUrl,
                                isPro: request.sender.isPro
                            )
                        },
                        titleFontSize: 14,
                        subtitleFontSize: 12,
                        imageSize: 48,
                        horizontalPadding: 12,
                        verticalPadding: 8
                    )
                }
            }

            // Friends section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your friends")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentM)
                        .tracking(-0.6)

                    Spacer()
                }

                if friends.isEmpty {
                    Text("No friends yet")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentM)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Constants.Surface)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    FriendList(
                        entries: friends.map { friend in
                            FriendListEntry(
                                id: "\(friend.friendshipId)",
                                name: friend.user.displayName,
                                subtitleText: String(localized: "\(friend.mutualFriendCount) mutual friends"),
                                avatarUrl: friend.user.avatarUrl,
                                isPro: friend.user.isPro
                            )
                        },
                        titleFontSize: 14,
                        subtitleFontSize: 12,
                        imageSize: 48,
                        horizontalPadding: 12,
                        verticalPadding: 8
                    )
                }
            }
        }
    }
}

#Preview {
    ProfileView()
        .environment(UserProfileService())
        .environment(PassportService())
        .environment(RealtimeService())
        .environment(StoreManager())
        .environment(NetworkMonitor.shared)
}
