//
//  InviteView.swift
//  OnePlan
//
//  Created by ken on 28/2/26.
//

import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct InviteView: View {
    var onScannedCode: (String) -> Void = { _ in }
    var openScannerOnAppear = false
    @Environment(UserProfileService.self) private var userProfileService

    @State private var scannerManager = QRScannerManager()
    @State private var friendService = FriendService()
    @State private var isScannerRevealed = false
    @State private var dragTranslation: CGFloat = 0
    @State private var lastScannedCode: String?

    private let openThreshold: CGFloat = 90
    private let closeThreshold: CGFloat = 90

    private var friendShareURL: URL? {
        guard let code = userProfileService.profile?.friendCode else { return nil }
        return DeepLinkBuilder.friendURL(code: code)
    }

    private var friendEntries: [FriendListEntry] {
        friendService.friends.map { friend in
            FriendListEntry(
                id: "\(friend.user.id)",
                name: friend.user.displayName,
                subtitleText: String(localized: "\(friend.mutualFriendCount) mutual friends"),
                avatarUrl: friend.user.avatarUrl,
                trailingAction: nil,
                isPro: friend.user.isPro
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let previewSize = min(max(0, proxy.size.width - 32), 360)
            let maxRevealOffset = previewSize + 20

            ZStack(alignment: .top) {
                scannerRevealLayer(
                    previewSize: previewSize,
                    maxRevealOffset: maxRevealOffset
                )

                contentContainer
                    .offset(y: activeOffset(maxRevealOffset: maxRevealOffset))
                    .gesture(
                        pullToRevealGesture()
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .onChange(of: isScannerRevealed) { _, isRevealed in
                if isRevealed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task {
                        await scannerManager.startScanning { payload in
                            lastScannedCode = payload
                            onScannedCode(payload)
                        }
                    }
                } else {
                    scannerManager.stopSession()
                }
            }
            .onDisappear {
                scannerManager.stopSession()
            }
        }
        .background(Constants.Background)
        .onAppear {
            guard openScannerOnAppear, !isScannerRevealed else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isScannerRevealed = true
            }
        }
        .task {
            await friendService.loadFriends()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(isScannerRevealed ? "Swipe up to close" : "Swipe down to scan")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Constants.ContentM)
                        .contentTransition(.opacity)
                        .animation(.default, value: isScannerRevealed)

                    Image(
                        systemName: isScannerRevealed
                            ? "chevron.up"
                            : "qrcode.viewfinder"
                    )
                        .font(.system(size: 16))
                        .foregroundColor(Constants.ContentM)
                }
            }
        }
    }

    private var contentContainer: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Group {
                        if let avatarUrl = userProfileService.profile?.avatarUrl,
                           let url = URL(string: avatarUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image("avatarPlaceholder")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        } else {
                            Image("avatarPlaceholder")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {

                        // Title
                        Text(userProfileService.profile?.displayName ?? "One Plan User")
                            .font(
                                Font.beVietnamPro(16, weight: .medium)
                            )
                            .foregroundColor(Constants.ContentB)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        // Note
                        Text("Hey! Let’s add friend and travel together.")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.ContentM)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(0)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    Rectangle()
                        .inset(by: 0.5)
                        .stroke(Constants.DividerStroke, lineWidth: 1)
                )

                if let friendCode = userProfileService.profile?.friendCode {
                    StyledQRCodeView(
                        content: DeepLinkBuilder.friendURL(code: friendCode).absoluteString,
                        color: Constants.BlueBase,
                        size: 222
                    )
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 222, height: 222)
                        .overlay {
                            ProgressView()
                        }
                }

                VStack {
                    HStack(alignment: .center, spacing: 12) {
                        Text(
                            verbatim: lastScannedCode
                                ?? friendShareURL?.absoluteString
                                ?? ""
                        )
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundColor(Constants.ContentB)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        if let url = friendShareURL {
                            ShareLink(
                                item: url,
                                subject: Text("Add me on OnePlan")
                            ) {
                                Chip(variant: .blue, text: String(localized: "Share"))
                            }
                        } else {
                            Chip(variant: .blue, text: "Share")
                                .opacity(0.4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Constants.OnSurface)
                    .cornerRadius(20)
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 0)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(Constants.Surface)
            .cornerRadius(32)

            VStack(alignment: .center, spacing: 12) {
                // Note
                Text("Friends · \(friendService.friends.count) friends")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentM)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                FriendList(
                    entries: friendEntries,
                    titleFontSize: 14,
                    subtitleFontSize: 12,
                    imageSize: 42,
                    horizontalPadding: 0
                )
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .top)
            .background(Constants.Surface)
            .cornerRadius(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func scannerRevealLayer(
        previewSize: CGFloat,
        maxRevealOffset: CGFloat
    ) -> some View {
        let revealProgress = min(
            1,
            max(0, activeOffset(maxRevealOffset: maxRevealOffset) / maxRevealOffset)
        )

        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Constants.OnSurface)

                if scannerManager.isAuthorized, scannerManager.getSession() != nil {
                    CameraPreviewView(session: scannerManager.getSession())
                        .clipShape(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                        )
                } else {
                    scannerFallbackView
                }
            }
            .frame(width: previewSize, height: previewSize)
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Constants.DividerStroke, lineWidth: 1)
            )
            .opacity(revealProgress)
            .padding(.top, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var scannerFallbackView: some View {
        VStack(spacing: 10) {
            Image(
                systemName: scannerManager.isAuthorized
                    ? "qrcode.viewfinder"
                    : "camera.fill.badge.xmark"
            )
            .font(.system(size: 30, weight: .semibold))
            .foregroundColor(Constants.ContentM)

            Text(scannerFallbackMessage)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentM)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.OnSurface)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var scannerFallbackMessage: String {
        if let errorMessage = scannerManager.error?.localizedDescription {
            return errorMessage
        }
        return "Camera preview is unavailable."
    }

    private func activeOffset(maxRevealOffset: CGFloat) -> CGFloat {
        let baseOffset = isScannerRevealed ? maxRevealOffset : 0
        return min(max(baseOffset + dragTranslation, 0), maxRevealOffset)
    }

    private func pullToRevealGesture() -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                let translation = value.translation.height
                let predicted = value.predictedEndTranslation.height

                if isScannerRevealed {
                    let shouldClose =
                        translation < -closeThreshold || predicted < -closeThreshold
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        if shouldClose {
                            isScannerRevealed = false
                        }
                        dragTranslation = 0
                    }
                } else {
                    let shouldOpen =
                        translation > openThreshold || predicted > openThreshold
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        if shouldOpen {
                            isScannerRevealed = true
                        }
                        dragTranslation = 0
                    }
                }
            }
    }
}

#Preview {
    InviteView()
        .environment(UserProfileService())
}
