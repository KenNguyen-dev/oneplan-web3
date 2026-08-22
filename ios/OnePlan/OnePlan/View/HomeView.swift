//
//  HomeView.swift
//  OnePlan
//
//  Created by ken on 26/2/26.
//

import CoreLocation
import SwiftUI

private struct HomeHistoryRoute: Identifiable, Hashable {
    let id = UUID()
    let tripId: Int
    var initialAddExpense = false
    var initialTab: TripTab? = nil
}

// Programmatic push into a marketplace listing from the Popular-plans
// polaroids. Hashed by listing id only — RecommendedMarketplaceItem itself
// isn't Hashable.
private struct HomeListingRoute: Identifiable, Hashable {
    let listingId: Int
    let item: RecommendedMarketplaceItem

    var id: Int { listingId }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.listingId == rhs.listingId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(listingId)
    }
}

struct HomeView: View {
    @Environment(RealtimeService.self) private var realtimeService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(StoreManager.self) private var storeManager
    @Environment(MarketplaceFeedService.self) private var marketplaceFeedService
    @Environment(\.scenePhase) private var scenePhase
    let tripService: TripService
    let tripDetailService: TripDetailService
    var onStartNewTripTapped: () -> Void = {}
    var onSwitchToBoardTab: () -> Void = {}
    @State private var selectedHistoryRoute: HomeHistoryRoute?
    @State private var selectedListingRoute: HomeListingRoute?
    @State private var navigateToPassport = false
    @State private var boardService = BoardService.shared
    @State private var sessionService = PinExtractionSessionService.shared
    // Paste-link / credit-gate flow shared with BoardView. Per-view instance
    // by design — see PinExtractionLauncher.
    @State private var launcher = PinExtractionLauncher()

    private var ongoingTrip: TripSummaryDto? {
        tripService.ongoingTrips.first
    }

    // Admin-featured listings first; trending fallback keeps the section
    // populated when nothing is featured.
    private var popularPlanItems: [RecommendedMarketplaceItem] {
        marketplaceFeedService.featuredItems.isEmpty
            ? marketplaceFeedService.recommendedItems
            : marketplaceFeedService.featuredItems
    }

    private var ongoingTripId: Int? {
        ongoingTrip.map { Int($0.id) }
    }

    var body: some View {
        AppScreenContainer {
            if tripService.isLoadingTrips {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        invitationBanner

                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            } else if !networkMonitor.isOnline && ongoingTrip == nil {
                VStack(spacing: 16) {
                    invitationBanner

                    Spacer(minLength: 0)
                    EmptyOffline()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            } else {
                homeContent
            }
        }
        .task {
            await loadHomeData()
            await storeManager.loadScanPackProducts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripLeft)) { _ in
            Task { await reloadHomeData() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .tripStatusChanged)
        ) { _ in
            Task { await reloadHomeData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripCreated)) {
            _ in
            Task { await reloadHomeData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .boardCreated)) { _ in
            Task { await boardService.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .boardUpdated)) { _ in
            Task { await boardService.load() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .pinExtractionSessionUpdated)
        ) { _ in
            Task {
                await sessionService.refresh()
                await launcher.loadBalance()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .scanCreditBalanceChanged)
        ) { _ in
            Task { await launcher.loadBalance() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Pull the active session whenever the app returns to foreground —
            // covers a push that fired while backgrounded (mirrors BoardView).
            if newPhase == .active {
                Task { await sessionService.refresh() }
            }
        }
        .onChange(of: networkMonitor.isOnline) { wasOnline, isOnline in
            // Came back online (cached ongoing trip or EmptyOffline) → reload.
            guard !wasOnline, isOnline else { return }
            Task { await reloadHomeData() }
        }
        .modifier(
            PinExtractionLauncherModifier(
                launcher: launcher,
                storeManager: storeManager,
                paywallContext: "home_gate"
            )
        )
        .navigationDestination(item: $selectedHistoryRoute) { route in
            TripDetailView(
                tripId: route.tripId,
                initialAddExpense: route.initialAddExpense,
                initialTab: route.initialTab,
                tripDetailService: tripDetailService
            )
        }
        .navigationDestination(item: $selectedListingRoute) { route in
            MarketItemDetailView(
                listingId: route.listingId,
                fallbackItem: route.item
            )
        }
        .navigationDestination(for: BoardSummaryDto.self) { board in
            BoardDetailView(board: board)
        }
        .navigationDestination(isPresented: $navigateToPassport) {
            PassportView()
        }
    }

    // MARK: - Content

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                invitationBanner

                if tripService.isServingCachedData {
                    OfflineBanner(cachedAt: nil)
                }

                if let ongoingTrip {
                    ongoingSection(for: ongoingTrip)
                }

                PinExtractionBanner(
                    preview: ActiveScanPreview(session: sessionService.activeSession),
                    isCheckingCredits: launcher.isCheckingCredits,
                    onPasteLink: { launcher.openPastedLink(source: "home_banner") },
                    onResume: { launcher.resume(sessionId: $0) }
                )

                QuickAccessSection(
                    onNewTripTapped: onStartNewTripTapped,
                    onPassportTapped: { navigateToPassport = true }
                )

                if !popularPlanItems.isEmpty {
                    PopularPlansSection(
                        items: popularPlanItems,
                        onItemTapped: { item in
                            guard let listingId = item.listingId else { return }
                            selectedListingRoute = HomeListingRoute(
                                listingId: listingId,
                                item: item
                            )
                        },
                        onSeeAll: {
                            NotificationCenter.default.post(
                                name: .switchToMarketTab,
                                object: nil
                            )
                        }
                    )
                }

                if !boardService.boards.isEmpty {
                    YourBoardsSection(
                        boards: boardService.boards,
                        onSeeAll: onSwitchToBoardTab
                    )
                }
            }
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, 16)
    }

    private func ongoingSection(for ongoingTrip: TripSummaryDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: "Ongoing")

            OngoingCard(
                tripName: ongoingTrip.name,
                coverImageUrl: ongoingTrip.coverImageUrl,
                locationLabel: formatLocation(ongoingTrip.location?.value1),
                memberAvatarUrls: ongoingTripMemberAvatarUrls(
                    for: Int(ongoingTrip.id)
                ),
                onCardTapped: {
                    selectedHistoryRoute = HomeHistoryRoute(
                        tripId: Int(ongoingTrip.id)
                    )
                },
                onNewExpenseTapped: {
                    selectedHistoryRoute = HomeHistoryRoute(
                        tripId: Int(ongoingTrip.id),
                        initialAddExpense: true
                    )
                }
            )

            if !todayPins.isEmpty {
                TodaysActivitiesCard(pins: todayPins) {
                    selectedHistoryRoute = HomeHistoryRoute(
                        tripId: Int(ongoingTrip.id),
                        initialTab: .yourPlan
                    )
                }
            }
        }
    }

    // MARK: - Today's plan pins

    // Today's plan items with coordinates, in timeline order (timed first by
    // start time, then untimed by sortOrder) — mirrors TripPlanSection's
    // dayMapPins derivation.
    private var todayPins: [PlanDayPin] {
        // The shared TripDetailService may hold another trip's items (Trip
        // tab); only trust them when they belong to the ongoing trip.
        guard let ongoingTripId,
              tripDetailService.trip?.id == ongoingTripId
        else { return [] }

        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: .now)

        let todaysItems = tripDetailService.allPlanItems
            .filter { $0.planDate == todayString }
            .sorted { lhs, rhs in
                // "HH:MM" strings order lexicographically; untimed items last.
                switch (lhs.startTime, rhs.startTime) {
                case let (l?, r?) where l != r: return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    if lhs.sortOrder != rhs.sortOrder {
                        return lhs.sortOrder < rhs.sortOrder
                    }
                    return lhs.id < rhs.id
                }
            }

        return todaysItems
            .compactMap { item -> (PlanItemDto, CLLocationCoordinate2D)? in
                guard let latitude = item.latitude, let longitude = item.longitude else {
                    return nil
                }
                return (item, CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            }
            .enumerated()
            .map { offset, located in
                PlanDayPin(
                    id: Int(located.0.id),
                    index: offset + 1,
                    title: located.0.title,
                    coordinate: located.1,
                    subtitle: located.0.location,
                    timeLabel: located.0.startTime
                )
            }
    }

    // MARK: - Invitation banner

    @ViewBuilder
    private var invitationBanner: some View {
        if let invite = realtimeService.pendingTripInvites.first {
            HStack(alignment: .center, spacing: 12) {
                invitationThumbnail(for: invite)

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            invite.invitedByDisplayName.isEmpty
                                ? "You’ve got an invitation to"
                                : "\(invite.invitedByDisplayName) invited you to"
                        )
                        .font(.beVietnamPro(14))
                        .tracking(-0.28)
                        .foregroundColor(Constants.ContentL)
                        .lineLimit(1)
                        .truncationMode(.tail)

                        Text(invite.tripName)
                            .font(.beVietnamPro(15))
                            .tracking(-0.3)
                            .foregroundColor(Constants.ContentB)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .center, spacing: 4) {
                        Button {
                            realtimeService.presentTripInvite(
                                inviteCode: invite.inviteCode
                            )
                        } label: {
                            Text("View")
                                .font(.beVietnamPro(14))
                                .tracking(-0.28)
                                .foregroundColor(Constants.White)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Constants.BlueBase)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            realtimeService.resolveTripInvite(
                                inviteCode: invite.inviteCode
                            )
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Constants.White)
                                .frame(width: 17, height: 17)
                                .padding(6)
                                .background(
                                    Color(red: 0.88, green: 0.15, blue: 0.14)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss invitation")
                    }
                }
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Constants.White)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.09), radius: 8.95, x: 0, y: 0)
        }
    }

    @ViewBuilder
    private func invitationThumbnail(for invite: RealtimeService.TripInviteState) -> some View {
        Group {
            if let coverImageUrl = invite.coverImageUrl,
                let url = URL(string: coverImageUrl)
            {
                CachedRemoteImage(
                    url: url,
                    targetSize: CGSize(width: 42, height: 42)
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image("defaultTripPlaceholder")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                Image("defaultTripPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(
            color: .black.opacity(0.15),
            radius: 15.642,
            x: 0,
            y: 1.955
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .inset(by: 0.24)
                .stroke(.black.opacity(0.15), lineWidth: 0.489)
        )
    }

    // MARK: - Helpers

    private func formatLocation(_ location: TripLocationDto?) -> String? {
        guard let location else { return nil }
        let parts = [location.cityName, location.countryName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func ongoingTripMemberAvatarUrls(for tripId: Int) -> [String?] {
        guard tripDetailService.trip?.id == tripId else {
            return []
        }

        return (tripDetailService.trip?.members ?? [])
            .filter { $0.inviteStatus.value1 == .ACCEPTED }
            .map(\.avatarUrl)
    }

    // MARK: - Data loading

    @MainActor
    private func loadHomeData(force: Bool = false) async {
        await tripService.listMyTrips(force: force)

        if let ongoingTripId {
            // Sequential on purpose: the dayNumber→planDate conversion inside
            // fetchAllTripPlanItems only runs once the ONGOING trip is loaded.
            await tripDetailService.loadTripDetail(
                tripId: ongoingTripId,
                force: force
            )
            // force: true — the shared service has no tripId guard on its
            // cached items, and the Trip tab may have loaded another trip.
            await tripDetailService.fetchAllTripPlanItems(
                tripId: ongoingTripId,
                force: true
            )
        }

        await boardService.loadIfNeeded(force: force)
        if force || marketplaceFeedService.recommendedItems.isEmpty {
            await marketplaceFeedService.listMarketplaceFeed(force: force)
        }
        await sessionService.refresh()
        await launcher.loadBalance()
    }

    @MainActor
    private func reloadHomeData() async {
        await loadHomeData(force: true)
    }
}

@MainActor
private struct HomeViewPreview: View {
    private let tripService: TripService
    private let tripDetailService: TripDetailService
    private let showOngoingTrip: Bool

    init(showOngoingTrip: Bool = true) {
        let tripService = TripService()
        let tripDetailService = TripDetailService()
        self.showOngoingTrip = showOngoingTrip

        if showOngoingTrip {
            Self.configurePreviewData(
                tripService: tripService,
                tripDetailService: tripDetailService
            )
        }

        self.tripService = tripService
        self.tripDetailService = tripDetailService
    }

    var body: some View {
        NavigationStack {
            HomeView(
                tripService: tripService,
                tripDetailService: tripDetailService
            )
        }
        .environment(RealtimeService())
        .environment(NetworkMonitor.shared)
        .environment(StoreManager())
        .environment(previewFeedService)
        .background(Constants.Background.ignoresSafeArea())
    }

    private var previewFeedService: MarketplaceFeedService {
        let service = MarketplaceFeedService()
        service.recommendedItems = [
            .init(
                creatorName: "Vivian",
                isCreatorVerified: false,
                title: "Singapore in 5 days",
                priceText: "Free",
                tags: [],
                listingId: 1,
                cityName: "Singapore"
            ),
            .init(
                creatorName: "Ken",
                isCreatorVerified: false,
                title: "London calling",
                priceText: "Free",
                tags: [],
                listingId: 2,
                countryName: "United Kingdom"
            ),
        ]
        return service
    }

    @MainActor
    private static func configurePreviewData(
        tripService: TripService,
        tripDetailService: TripDetailService
    ) {
        let previewMembers: [TripMemberDto] = [
            .init(
                id: 1,
                userId: 1,
                displayName: "Ken",
                avatarUrl: nil,
                friendCode: "KEN001",
                inviteStatus: .init(value1: .ACCEPTED),
                role: .init(value1: .MEMBER),
                joinedAt: "2026-05-15T08:30:00Z",
                isPro: true
            ),
            .init(
                id: 2,
                userId: 2,
                displayName: "Mina",
                avatarUrl: nil,
                friendCode: "MINA02",
                inviteStatus: .init(value1: .ACCEPTED),
                role: .init(value1: .MEMBER),
                joinedAt: "2026-05-15T09:10:00Z",
                isPro: false
            ),
            .init(
                id: 3,
                userId: 3,
                displayName: "Bao",
                avatarUrl: nil,
                friendCode: "BAO003",
                inviteStatus: .init(value1: .ACCEPTED),
                role: .init(value1: .MEMBER),
                joinedAt: "2026-05-15T09:42:00Z",
                isPro: false
            ),
            .init(
                id: 4,
                userId: 4,
                displayName: "Linh",
                avatarUrl: nil,
                friendCode: "LINH04",
                inviteStatus: .init(value1: .ACCEPTED),
                role: .init(value1: .MEMBER),
                joinedAt: "2026-05-15T10:05:00Z",
                isPro: false
            ),
        ]

        let previewLocation = TripLocationDto(
            cityId: 1581130,
            stateId: nil,
            countryId: 704,
            cityName: "Da Nang",
            stateName: nil,
            countryName: "Vietnam",
            latitude: 16.0678,
            longitude: 108.2208
        )

        let todayString: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: .now)
        }()

        tripService.ongoingTrips = [
            .init(
                id: 42,
                name: "Da Nang Friends Escape",
                coverImageUrl: nil,
                status: .init(value1: .ONGOING),
                startDate: "2026-05-16",
                endDate: "2026-05-21",
                memberCount: previewMembers.count,
                lastSeenChatMessageId: nil,
                currency: .init(value1: .VND),
                location: .init(value1: previewLocation)
            )
        ]

        tripDetailService.trip = .init(
            id: 42,
            name: "Da Nang Friends Escape",
            coverImageUrl: nil,
            status: .init(value1: .ONGOING),
            startDate: "2026-05-16",
            endDate: "2026-05-21",
            inviteCode: "DANANG26",
            createdById: 1,
            createdAt: "2026-05-10T10:00:00Z",
            currency: .init(value1: .VND),
            localCurrencies: [],
            location: .init(value1: previewLocation),
            marketplaceListingId: nil,
            userMarketplaceRating: nil,
            members: previewMembers
        )

        tripDetailService.allPlanItems = [
            .init(
                id: 201,
                tripId: 42,
                planDate: todayString,
                title: "Morning coffee at The Espresso Station",
                description: nil,
                location: "The Espresso Station",
                latitude: 16.0678,
                longitude: 108.2208,
                address: nil,
                startTime: "08:00",
                category: nil,
                voiceUrl: nil,
                voiceDuration: nil,
                dayNumber: 4,
                sortOrder: 0,
                createdAt: "2026-05-10T10:00:00Z",
                members: []
            ),
            .init(
                id: 202,
                tripId: 42,
                planDate: todayString,
                title: "Dragon Bridge walk",
                description: nil,
                location: "Dragon Bridge",
                latitude: 16.0614,
                longitude: 108.2277,
                address: nil,
                startTime: "10:30",
                category: nil,
                voiceUrl: nil,
                voiceDuration: nil,
                dayNumber: 4,
                sortOrder: 1,
                createdAt: "2026-05-10T10:00:00Z",
                members: []
            ),
        ]
    }
}

#Preview("Ongoing trip") {
    HomeViewPreview()
}

#Preview("No ongoing trip") {
    HomeViewPreview(showOngoingTrip: false)
}
