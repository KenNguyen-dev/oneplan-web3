//
//  BoardView.swift
//  OnePlan
//
//  Created by ken on 11/5/26.
//

import Foundation
import StoreKit
import SwiftUI

// Identifiable wrapper for programmatic pushes to BoardDetailView (mirrors
// TripView's TripOngoingRoute pattern — BoardSummaryDto is Hashable but not
// Identifiable, and BoardDetailView only takes a BoardSummaryDto).
private struct BoardDetailRoute: Identifiable, Hashable {
    let board: BoardSummaryDto
    var id: Int { board.id }
}

struct BoardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(StoreManager.self) private var storeManager
    @State private var logosFannedOut = false
    @State private var isCreateBoardSheetPresented = false
    @State private var boardDetailRoute: BoardDetailRoute?
    @State private var boardService = BoardService.shared
    @State private var sessionService = PinExtractionSessionService.shared
    @State private var deepLinkRouter = DeepLinkRouter.shared
    // Paste-link / credit-gate flow shared with HomeView. Per-view instance
    // by design — see PinExtractionLauncher.
    @State private var launcher = PinExtractionLauncher()

    // Derived from sessionService.activeSession. Returns nil when there's
    // no in-flight or undismissed extraction.
    private var activeScanPreview: ActiveScanPreview? {
        ActiveScanPreview(session: sessionService.activeSession)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // The scanning card replaces the "Import via link" hero
                // entirely while a session is active — paste-link is locked
                // out anyway (server rejects a second extraction), so the
                // hero would be misleading next to it.
                if let preview = activeScanPreview {
                    BoardScanningCard(
                        preview: preview,
                        onCancel: {
                            Task { await sessionService.cancel(sessionId: preview.sessionId) }
                        },
                        onResume: {
                            launcher.resume(sessionId: preview.sessionId)
                        }
                    )
                } else {
                    createBoardHero
                }
                boardList
            }
            .padding()
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Constants.Background.ignoresSafeArea())
        .task {
            // Cold launch from the Share Extension: the link is already queued
            // before BoardView mounts, so `.onChange` would never fire — pick it
            // up here at mount. Single-shot consume keeps it idempotent with the
            // warm-path `.onChange` below.
            consumePendingExtractionURLIfNeeded()
            AnalyticsClient.shared.track(.BOARD_OPENED)
            await boardService.loadIfNeeded()
            await sessionService.refresh()
            await launcher.loadBalance()
            await storeManager.loadScanPackProducts()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Pull the active session whenever the app returns to
            // foreground — covers the case where a push fired while the
            // app was backgrounded and we need to update the card.
            if newPhase == .active {
                Task {
                    await sessionService.refresh()
                    await launcher.loadBalance()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .boardCreated)) { _ in
            Task { await boardService.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .boardUpdated)) { _ in
            Task { await boardService.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinExtractionSessionUpdated)) { _ in
            Task {
                await sessionService.refresh()
                await launcher.loadBalance()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanCreditBalanceChanged)) { _ in
            Task { await launcher.loadBalance() }
        }
        .onChange(of: deepLinkRouter.pendingPinExtractionSessionId) { _, newValue in
            // Push fired while app was backgrounded (or user tapped a
            // foreground banner-equivalent surface). Consume here and
            // navigate into ProcessPinView for that session.
            if let id = newValue {
                _ = deepLinkRouter.consumePendingPinExtractionSessionId()
                launcher.resume(sessionId: id)
            }
        }
        .onChange(of: deepLinkRouter.pendingPinExtractionURL) { _, newValue in
            // Share Extension link arrived while BoardView is already mounted
            // (warm, on the Board tab). The cold-launch case is handled in
            // `.task` instead. Consume drives the same credit-gated start.
            if newValue != nil {
                consumePendingExtractionURLIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openBoardDetail)) { note in
            // ProcessPinView attached pins to a board. BoardView is the SOLE
            // owner of this pop+push: clear pendingExtraction (pops
            // ProcessPinView), then push BoardDetailView for that board.
            guard let boardId = note.userInfo?["boardId"] as? Int else { return }
            launcher.pendingExtraction = nil
            Task {
                if boardService.boards.first(where: { $0.id == boardId }) == nil {
                    // Defensive: addPins updates the cached entry in place and
                    // createBoard inserts the new board, so this normally hits
                    // the cache — covers a never-loaded edge only.
                    await boardService.load()
                }
                guard let board = boardService.boards.first(where: {
                    $0.id == boardId
                }) else { return }
                // Let the pop — and, in the Create-Board sub-flow, the
                // CreateBoardBottomSheet dismissing concurrently — settle
                // before pushing onto MainView's single NavigationStack.
                // 0.35s ≈ the proven .tripCreated 0.3s settle precedent.
                try? await Task.sleep(for: .seconds(0.35))
                boardDetailRoute = BoardDetailRoute(board: board)
            }
        }
        .modifier(
            PinExtractionLauncherModifier(
                launcher: launcher,
                storeManager: storeManager,
                paywallContext: "board_gate"
            )
        )
        .navigationDestination(for: BoardSummaryDto.self) { board in
            BoardDetailView(board: board)
        }
        .navigationDestination(item: $boardDetailRoute) { route in
            BoardDetailView(board: route.board)
        }
        .sheet(isPresented: $isCreateBoardSheetPresented) {
            CreateBoardBottomSheet()
        }
    }

    private var createBoardHero: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [
                        Color(red: 0.85, green: 0.94, blue: 1),
                        Constants.White
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    heroLogoStack

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Import via link")
                            .font(.custom("Be Vietnam Pro", size: 16))
                            .foregroundStyle(Constants.Neutral950)
                            .tracking(-0.64)
                            .lineLimit(1)

                        Text("Save pin throughout your favorite Tik Tok video or Instagram video. Copy URL and paste it here.")
                            .font(.custom("Be Vietnam Pro", size: 13))
                            .foregroundStyle(Constants.Neutral600)
                            .tracking(-0.65)
                            .lineSpacing(0)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                Button {
                    launcher.showBuyCredits = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Constants.Neutral600)
                        Text(launcher.creditLabel)
                            .foregroundStyle(Constants.Neutral950)
                    }
                    .font(.custom("Be Vietnam Pro", size: 15))
                    .tracking(-0.3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffectCompat()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan credits")
                .accessibilityValue(launcher.creditLabel)
                .padding(10)
            }
            .frame(height: 146)

            Button {
                launcher.openPastedLink()
            } label: {
                Group {
                    if launcher.isCheckingCredits {
                        ProgressView()
                            .tint(Constants.White)
                    } else {
                        Text("Paste link")
                            .font(.custom("Be Vietnam Pro", size: 17))
                            .tracking(-0.68)
                            .foregroundStyle(Constants.White)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Constants.Black, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 1)
                .shadow(color: .black.opacity(0.10), radius: 2, x: 0, y: 0)
            }
            .buttonStyle(.plain)
            .disabled(launcher.isCheckingCredits)
        }
        .padding(8)
        .background(Color(red: 0.16, green: 0.60, blue: 0.97), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var heroLogoStack: some View {
        HStack(spacing: -15) {
            Image("boardInstagramLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .rotationEffect(.degrees(logosFannedOut ? -4.5 : 0))
                .scaleEffect(logosFannedOut ? 1 : 0.88)
                .offset(x: logosFannedOut ? 0 : 12, y: logosFannedOut ? 0 : 6)

            Image("boardTikTokLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .rotationEffect(.degrees(logosFannedOut ? 4.62 : 0))
                .scaleEffect(logosFannedOut ? 1 : 0.88)
                .offset(x: logosFannedOut ? 0 : -12, y: logosFannedOut ? 0 : 6)
                .zIndex(1)
        }
        .onAppear {
            guard !logosFannedOut else { return }

            if reduceMotion {
                logosFannedOut = true
            } else {
                withAnimation(.bouncy(duration: 0.62, extraBounce: 0.12).delay(0.18)) {
                    logosFannedOut = true
                }
            }
        }
    }

    private var boardList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Boards")
                .font(.beVietnamPro(16, weight: .medium))
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)

            if boardService.boards.isEmpty && !boardService.isLoading {
                BoardEmptyState()
            } else {
                ForEach(boardService.boards, id: \.id) { board in
                    NavigationLink(value: board) {
                        BoardSummaryRow(board: board)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                triggerPrimaryHaptic()
                isCreateBoardSheetPresented = true
            } label: {
                CreateBoardButtonContent()
            }
            .buttonStyle(.plain)
        }
    }

    // Share Extension flow: consume the queued link (single-shot) and run it
    // through the same credit gate as a pasted link. Called at mount (`.task`)
    // for the cold-launch case and on `.onChange` for the warm case.
    // Deliberately kept here (not in the launcher) — BoardView is the sole
    // owner of the Share-Extension / push deep-link hand-off.
    private func consumePendingExtractionURLIfNeeded() {
        guard let link = deepLinkRouter.consumePendingPinExtractionURL() else {
            return
        }
        launcher.startExtraction(for: link, source: "share_extension")
    }

    private func triggerPrimaryHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

}

private struct BoardEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image("emptyBoard")
                .resizable()
                .scaledToFit()
                .frame(width: 154, height: 159)
                .accessibilityHidden(true)

            Text("No board created.")
                .font(.beVietnamPro(16, weight: .medium))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.32)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 321)
        .background(Constants.Surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct CreateBoardButtonContent: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("createBoardThumbnail")
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .background(Constants.White)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 7.82, x: 0, y: 0.98)
                .accessibilityHidden(true)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create your list with")
                        .font(.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.White.opacity(0.5))
                        .tracking(-0.28)
                        .lineLimit(1)

                    Text("Boards")
                        .font(.custom("Be Vietnam Pro", size: 15))
                        .foregroundStyle(Constants.White)
                        .tracking(-0.3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("New Board")
                    .font(.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-0.28)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Constants.White, in: Capsule())
            }
            .padding(.trailing, 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.BlueBase, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.09), radius: 8.95, x: 0, y: 0)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct BoardScanningCard: View {
    let preview: ActiveScanPreview
    let onCancel: () -> Void
    let onResume: () -> Void

    private var heroBlue: Color { Color(red: 0.16, green: 0.60, blue: 0.97) }

    var body: some View {
        VStack(spacing: 8) {
            scanCard
            HStack(spacing: 8) {
                SecondaryButton(
                    title: "\(preview.cancelLabel)",
                    variant: preview.cancelVariant,
                    action: onCancel
                )
                .frame(maxWidth: .infinity)

                PrimaryButton(title: "\(preview.resumeLabel)", action: onResume)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .background(heroBlue, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var scanCard: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
                .frame(width: 110, height: 142)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image("processPinLightStars")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)

                    Text(preview.stateLabel)
                        .font(.custom("Be Vietnam Pro", size: 15))
                        .foregroundStyle(Constants.White)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.28), value: preview.stateLabel)
                }

                Rectangle()
                    .fill(Constants.White.opacity(0.12))
                    .frame(height: 1)

                Text(preview.title)
                    .font(.beVietnamPro(16, weight: .medium))
                    .foregroundStyle(Constants.White)
                    .tracking(-0.32)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Image("boardCompassIcon")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Constants.White.opacity(0.55))

                    Text(preview.platform.label)
                        .font(.custom("Be Vietnam Pro", size: 14))
                        .tracking(-0.28)
                        .foregroundStyle(Constants.White.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Constants.Black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = preview.thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty, .failure:
                    placeholderThumbnail
                @unknown default:
                    placeholderThumbnail
                }
            }
        } else {
            placeholderThumbnail
        }
    }

    private var placeholderThumbnail: some View {
        Image("boardPlaceholder")
            .resizable()
            .scaledToFill()
    }
}

#Preview {
    ZStack {
        Constants.Background
            .ignoresSafeArea()

        BoardView()
            .padding(.horizontal, 0)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
