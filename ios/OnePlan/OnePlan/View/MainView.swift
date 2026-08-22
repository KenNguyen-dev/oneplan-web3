//
//  MainView.swift
//  OnePlan
//
//  Created by ken on 12/3/26.
//

import SwiftUI
import UIKit

// MARK: - Tab Definition

enum AppTab: String, MorphingTabProtocol {
    case home, trip, chat, market

    var symbolImage: String {
        switch self {
        case .home: "home"
        case .trip: "planet"
        case .chat: "board"
        case .market: "suitcase"
        }
    }

    var selectedSymbolImage: String {
        switch self {
        case .home: "homeBlue"
        case .trip: "planetBlue"
        case .chat: "boardBlue"
        case .market: "suitcaseBlue"
        }
    }

    // Rendered via Core Graphics (`NSString.draw`) in MorphingTabBar, not a
    // SwiftUI `Text`, so it can't auto-localize — resolve explicitly here.
    var title: String {
        switch self {
        case .home: String(localized: "Home", comment: "Home tab title")
        case .trip: String(localized: "Trip", comment: "Trip tab title")
        case .chat: String(localized: "Board", comment: "Board tab title")
        case .market: String(localized: "Market", comment: "Market tab title")
        }
    }
}

// MARK: - Quick Action Model

struct QuickAction: Identifiable {
    enum Kind: String, Identifiable {
        case scanQR
        case newTrip
        case uploadTrip

        var id: String { rawValue }
    }

    let id: Kind
    let icon: String
    let title: String
}

// `title` is shown via `Text(action.title)` (a `String`, not a literal), so it
// is resolved here with `String(localized:)` rather than auto-localized.
private let quickActions: [QuickAction] = [
    QuickAction(
        id: .scanQR,
        icon: "qrcode.viewfinder",
        title: String(localized: "Scan QR", comment: "Quick action: open QR scanner")
    ),
    QuickAction(
        id: .newTrip,
        icon: "globe.americas",
        title: String(localized: "New trip", comment: "Quick action: create a trip")
    ),
    QuickAction(
        id: .uploadTrip,
        icon: "square.and.arrow.up",
        title: String(localized: "Upload Trip", comment: "Quick action: publish a trip plan (Pro)")
    ),
]

// MARK: - Glass Button Style

struct PlainGlassButtonEffect<S: Shape>: ButtonStyle {
    var shape: S
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffectCompat(in: shape)
    }
}

// MARK: - Main View

struct MainView: View {
    @Binding var deepLinkTripId: Int?
    @Binding var deepLinkChatTripId: Int?
    @Binding var deepLinkPlanItem: PlanItemDeepLink?
    @Binding var deepLinkListingId: IdentifiableInt?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(StoreManager.self) private var storeManager
    @Environment(UserProfileService.self) private var userProfileService
    var onScannedFriendCode: (String) -> Void = { _ in }
    @State private var activeTab: AppTab
    @State private var deepLinkRouter = DeepLinkRouter.shared
    @State private var isExpanded: Bool = false
    @State private var selectedActionIndex: Int?
    @State private var navigateToCreateTrip = false
    @State private var navigateToProfile = false
    /// When Profile is pushed from welcome "Add money", also open wallet (+ deposit).
    @State private var profileOpenWalletOnAppear = false
    @State private var profileOpenDepositOnAppear = false
    @State private var navigateToEndedTrips = false
    @State private var navigateToUnlockedMarketPlans = false
    @State private var navigateToUploadTrip = false
    @State private var showFriendQRScanner = false
    @State private var showingTripLimitPaywall = false
    @State private var isShowingRequestPlanSheet = false
    @State private var requestDestination: SelectedMarketDestination?
    @State private var requestSelectedTag: Components.Schemas.ListingTag = .FRIENDS
    @State private var requestBudgetText = ""
    @State private var selectedRequestCurrency: Currency? = .VND
    @State private var tripRequestService = TripRequestService()
    @State private var tripRequestAlert: TripRequestAlert?

    // Shared services - cached across all tabs
    @State private var tripService = TripService()
    @State private var tripDetailService = TripDetailService()
    @State private var marketplaceFeedService = MarketplaceFeedService()
    @State private var myAcquisitionsService = MyAcquisitionsService()
    @State private var mapSearchService = MapSearchService()

    init(
        deepLinkTripId: Binding<Int?>,
        deepLinkChatTripId: Binding<Int?> = .constant(nil),
        deepLinkPlanItem: Binding<PlanItemDeepLink?> = .constant(nil),
        deepLinkListingId: Binding<IdentifiableInt?> = .constant(nil),
        onScannedFriendCode: @escaping (String) -> Void = { _ in },
        initialTab: AppTab = .home
    ) {
        self._deepLinkTripId = deepLinkTripId
        self._deepLinkChatTripId = deepLinkChatTripId
        self._deepLinkPlanItem = deepLinkPlanItem
        self._deepLinkListingId = deepLinkListingId
        self.onScannedFriendCode = onScannedFriendCode
        self._activeTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ZStack {
                    activeTabContent
                        .id(activeTab)
                        .transition(.opacity)
                        .refreshable {
                            await refreshMainData()
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(alignment: .bottom, spacing: 12) {
                    MorphingTabBar(
                        activeTab: tabSelectionBinding,
                        isExpanded: $isExpanded
                    ) {
                        expandedContent
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light)
                            .impactOccurred()
                        withAnimation(.bouncy(duration: 0.5, extraBounce: 0.05))
                        {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .rotationEffect(.init(degrees: isExpanded ? 45 : 0))
                            .frame(width: 58, height: 58)
                            .foregroundStyle(Color.primary)
                            .contentShape(.circle)
                    }
                    .buttonStyle(PlainGlassButtonEffect(shape: .circle))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 25)
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .onAppear {
                if deepLinkChatTripId != nil
                    || deepLinkRouter.pendingPinExtractionSessionId != nil
                    || deepLinkRouter.pendingPinExtractionURL != nil
                {
                    // Board tab is `.chat` (legacy enum naming) — used
                    // for both trip chat AND board content.
                    switchTab(to: .chat)
                } else if deepLinkTripId != nil || deepLinkPlanItem != nil {
                    switchTab(to: .trip)
                } else if deepLinkListingId != nil {
                    switchTab(to: .market)
                } else if deepLinkRouter.pendingOpenBoard {
                    _ = deepLinkRouter.consumePendingOpenBoard()
                    switchTab(to: .chat)
                } else if deepLinkRouter.pendingOpenMarket {
                    _ = deepLinkRouter.consumePendingOpenMarket()
                    switchTab(to: .market)
                }
            }
            .task {
                await mapSearchService.configureWithUserLocation()
            }
            .onChange(of: deepLinkTripId) { _, newValue in
                if newValue != nil {
                    switchTab(to: .trip)
                }
            }
            .onChange(of: deepLinkChatTripId) { _, newValue in
                if newValue != nil {
                    switchTab(to: .chat)
                }
            }
            .onChange(of: deepLinkPlanItem) { _, newValue in
                if newValue != nil {
                    switchTab(to: .trip)
                }
            }
            .onChange(of: deepLinkListingId) { _, newValue in
                if newValue != nil {
                    switchTab(to: .market)
                }
            }
            .onChange(of: deepLinkRouter.pendingPinExtractionSessionId) { _, newValue in
                // Don't consume — BoardView (mounted on `.chat`) is the
                // owner of this deep-link payload and pushes ProcessPinView.
                if newValue != nil {
                    switchTab(to: .chat)
                }
            }
            .onChange(of: deepLinkRouter.pendingPinExtractionURL) { _, newValue in
                // Share Extension link. Don't consume — BoardView owns it and
                // runs it through the credit gate. Just surface the Board tab.
                if newValue != nil {
                    switchTab(to: .chat)
                }
            }
            .onChange(of: deepLinkRouter.pendingOpenBoard) { _, newValue in
                if newValue {
                    _ = deepLinkRouter.consumePendingOpenBoard()
                    switchTab(to: .chat)
                }
            }
            .onChange(of: deepLinkRouter.pendingOpenMarket) { _, newValue in
                if newValue {
                    _ = deepLinkRouter.consumePendingOpenMarket()
                    switchTab(to: .market)
                }
            }
            .navigationDestination(isPresented: $navigateToCreateTrip) {
                CreateTripView()
            }
            .navigationDestination(isPresented: $navigateToProfile) {
                ProfileView(
                    openWalletOnAppear: profileOpenWalletOnAppear,
                    openDepositOnAppear: profileOpenDepositOnAppear
                )
            }
            .navigationDestination(isPresented: $navigateToEndedTrips) {
                ScrollView {
                    EndedTripView(trips: tripService.endedTrips)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationDestination(isPresented: $navigateToUnlockedMarketPlans)
            {
                UnlockedMarketPlanView(
                    acquisitionsService: myAcquisitionsService
                )
            }
            .navigationDestination(isPresented: $navigateToUploadTrip) {
                UploadTripView(service: tripDetailService)
            }
            .navigationDestination(item: $deepLinkListingId) { wrapper in
                MarketItemDetailView(
                    listingId: wrapper.id,
                    fallbackItem: nil,
                    tripId: nil
                )
            }
            .navigationDestination(isPresented: $showFriendQRScanner) {
                InviteView(
                    onScannedCode: { payload in
                        if let code = parseFriendCode(from: payload) {
                            showFriendQRScanner = false
                            onScannedFriendCode(code)
                        } else if let inviteURL = buildJoinURL(from: payload) {
                            showFriendQRScanner = false
                            openURL(inviteURL)
                        }
                    },
                    openScannerOnAppear: true
                )
            }
            .sheet(isPresented: $showingTripLimitPaywall) {
                SubscriptionView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .tripCreated))
            { notification in
                Task {
                    await tripService.listMyTrips(force: true)
                }

                if let tripId = notification.userInfo?["tripId"] as? Int {
                    isExpanded = false
                    selectedActionIndex = nil
                    navigateToCreateTrip = false
                    navigateToProfile = false
                    switchTab(to: .home)
                    deepLinkTripId = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        deepLinkTripId = tripId
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .switchToMarketTab)
            ) { _ in
                switchTab(to: .market)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openOnePlanWallet)
            ) { note in
                let openDeposit = note.userInfo?["openDeposit"] as? Bool ?? false
                profileOpenWalletOnAppear = true
                profileOpenDepositOnAppear = openDeposit
                switchTab(to: .home)
                // Remount Profile with the open-wallet flags if it was already up.
                navigateToProfile = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    navigateToProfile = true
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openTripDetail)
            ) { note in
                // ProcessPinView attached pins to a trip — take the user to
                // that trip's TripDetailView. This is the EXACT proven
                // .tripCreated recipe: nil deepLinkTripId, then set it after
                // 0.3s and let MainView.onChange(of: deepLinkTripId) drive
                // switchTab(to: .trip). That .chat → .trip switch is a real
                // tab change (ProcessPinView is only reachable from the Board
                // tab), so TripView remounts FRESH with deepLinkTripId already
                // set and its .onChange(initial: true) deterministically
                // appends tripId at mount → TripDetailView.
                //
                // Do NOT call switchTab(to: .trip) here: pre-switching makes
                // the onChange-driven switch a guarded no-op, so TripView
                // mounts before the value is set and the trip never opens.
                guard let tripId = note.userInfo?["tripId"] as? Int else {
                    return
                }
                deepLinkTripId = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    deepLinkTripId = tripId
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Button {
                            profileOpenWalletOnAppear = false
                            profileOpenDepositOnAppear = false
                            navigateToProfile = true
                        } label: {
                            Group {
                                if let avatarUrl = userProfileService.profile?
                                    .avatarUrl,
                                    let url = URL(string: avatarUrl)
                                {
                                    CachedRemoteImage(
                                        url: url,
                                        targetSize: CGSize(
                                            width: 32,
                                            height: 32
                                        )
                                    ) { image in
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
                            .frame(width: 32, height: 32)
                            .padding(0)
                            .clipShape(.circle)
                        }
                        .buttonStyle(.plain)

                        if let displayName = userProfileService.profile?
                            .displayName
                        {
                            Button {
                                profileOpenWalletOnAppear = false
                                profileOpenDepositOnAppear = false
                                navigateToProfile = true
                            } label: {
                                // Match ToolbarIconButton: black text on the
                                // glass capsule (white material fallback below
                                // iOS 26) instead of the tinted `.bordered` look.
                                Text(displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Constants.ContentB)
                                    .lineLimit(1)
                                    .fixedSize(
                                        horizontal: true,
                                        vertical: false
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .glassEffectCompat(in: Capsule())
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .sharedBackgroundHiddenCompat()

                if activeTab != .chat {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        topTrailingToolbarContent
                    }
                    .sharedBackgroundHiddenCompat()
                }
            }
        }
        .sheet(isPresented: $isShowingRequestPlanSheet) {
            RequestTripBottomSheetContent(
                destinationText: requestDestination?.mostSpecificName,
                selectedTag: $requestSelectedTag,
                selectedCurrency: $selectedRequestCurrency,
                budgetText: $requestBudgetText,
                onLocationSelected: { city, state, country in
                    requestDestination = SelectedMarketDestination(
                        cityId: city?.id,
                        stateId: state.id,
                        countryId: country.id,
                        cityName: city?.name,
                        stateName: state.name,
                        countryName: country.name
                    )
                },
                isSubmitting: tripRequestService.isSubmitting,
                onSubmit: {
                    submitTripRequest()
                }
            )
            .presentationDetents([.height(476)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(44)
            .presentationBackground(Constants.Surface)
        }
        .alert(
            tripRequestAlert?.title ?? "",
            isPresented: Binding(
                get: { tripRequestAlert != nil },
                set: { if !$0 { tripRequestAlert = nil } }
            ),
            presenting: tripRequestAlert
        ) { _ in
            Button(String(localized: "OK"), role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .environment(marketplaceFeedService)
    }

    private func submitTripRequest() {
        guard let destination = requestDestination else {
            tripRequestAlert = TripRequestAlert(
                title: String(localized: "Destination required"),
                message: String(localized: "Please choose where you want to go before submitting.")
            )
            return
        }
        guard !tripRequestService.isSubmitting else { return }

        let budgetDigits = requestBudgetText.filter { $0.isASCII && $0.isNumber }
        let budget = budgetDigits.isEmpty ? nil : Double(budgetDigits)
        let currency = (selectedRequestCurrency ?? .VND).apiCurrencyOrFallback

        Task {
            do {
                try await tripRequestService.submitRequest(
                    destination: destination,
                    tag: requestSelectedTag,
                    budget: budget,
                    currency: currency
                )
                isShowingRequestPlanSheet = false
                requestDestination = nil
                requestSelectedTag = .FRIENDS
                requestBudgetText = ""
                selectedRequestCurrency = .VND
                tripRequestAlert = TripRequestAlert(
                    title: String(localized: "Request submitted"),
                    message: String(localized: "We'll send you a notification when the plan is available.")
                )
            } catch TripRequestError.duplicateOpenRequest {
                tripRequestAlert = TripRequestAlert(
                    title: String(localized: "Request already open"),
                    message: String(localized: "You already have an open request for this destination.")
                )
            } catch {
                tripRequestAlert = TripRequestAlert(
                    title: String(localized: "Something went wrong"),
                    message: String(localized: "We couldn't submit your request. Please try again.")
                )
            }
        }
    }

    private var tabSelectionBinding: Binding<AppTab> {
        Binding(
            get: { activeTab },
            set: { newTab in
                switchTab(to: newTab)
            }
        )
    }

    private var tabSwitchAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch activeTab {
        case .home:
            HomeView(
                tripService: tripService,
                tripDetailService: tripDetailService,
                onStartNewTripTapped: {
                    switchTab(to: .trip)
                    openCreateTripFlow()
                },
                onSwitchToBoardTab: {
                    switchTab(to: .chat)
                }
            )
        case .trip:
            TripView(
                deepLinkTripId: $deepLinkTripId,
                deepLinkPlanItem: $deepLinkPlanItem,
                tripService: tripService,
                tripDetailService: tripDetailService
            )
        case .chat:
            BoardView()
        case .market:
            MarketView(
                marketplaceFeedService: marketplaceFeedService
            )
        }
    }

    private func switchTab(to newTab: AppTab) {
        guard newTab != activeTab else { return }

        if let tabSwitchAnimation {
            withAnimation(tabSwitchAnimation) {
                activeTab = newTab
            }
        } else {
            activeTab = newTab
        }
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

    private func buildJoinURL(from payload: String) -> URL? {
        guard let code = parseInviteCode(from: payload)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return nil }
        return DeepLinkBuilder.customSchemeJoin(code: code)
    }

    @ViewBuilder
    private var topTrailingToolbarContent: some View {
        switch activeTab {
        case .home, .trip:
            ToolbarIconButton(
                systemName: "clock.arrow.circlepath",
                horizontalPadding: 10,
                verticalPadding: 10
            ) {
                handleHomeTripTrailingTap()
            }

        case .market:
            HStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .light)
                        .impactOccurred()
                    isShowingRequestPlanSheet = true
                } label: {
                    Text("Request a plan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Constants.ContentB)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .glassEffectCompat(in: Capsule())
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)

                ToolbarIconButton(
                    systemName: "bag.fill",
                    horizontalPadding: 10,
                    verticalPadding: 10
                ) {
                    navigateToUnlockedMarketPlans = true
                }
            }

        case .chat:
            EmptyView()
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(quickActions.enumerated()), id: \.element.id) {
                index,
                action in
                PremiumGate(
                    allowed: isQuickActionAllowed(action),
                    dimsWhenBlocked: false
                ) {
                    Button {
                        selectedActionIndex = index
                        withAnimation(.bouncy(duration: 0.5, extraBounce: 0.05))
                        {
                            isExpanded = false
                        }
                        handleQuickAction(action)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: action.icon)
                                .font(.system(size: 20))
                                .frame(width: 28)
                                .foregroundStyle(Color.primary)

                            Text(action.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if action.id == .uploadTrip {
                                ProBadge()
                                    .fixedSize()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            selectedActionIndex == index
                                ? Color.gray.opacity(0.06)
                                : Color.clear,
                            in: .capsule
                        )
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
    }

    private func isQuickActionAllowed(_ action: QuickAction) -> Bool {
        switch action.id {
        case .uploadTrip:
            storeManager.isPro
        case .scanQR, .newTrip:
            true
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        switch action.id {
        case .scanQR:
            showFriendQRScanner = true
        case .newTrip:
            openCreateTripFlow()
        case .uploadTrip:
            openUploadTripFlow()
        }
    }

    private func openUploadTripFlow() {
        guard storeManager.isPro else {
            showingTripLimitPaywall = true
            return
        }

        navigateToUploadTrip = true
    }

    private func openCreateTripFlow() {
        if tripService.canCreatePlanningTrip(isPro: storeManager.isPro) {
            navigateToCreateTrip = true
        } else {
            showingTripLimitPaywall = true
        }
    }

    private func handleHomeTripTrailingTap() {
        navigateToEndedTrips = true
        if tripService.endedTrips.isEmpty {
            Task { await tripService.listMyTrips() }
        }
    }

    @MainActor
    private func refreshMainData() async {
        async let tripsTask: () = tripService.listMyTrips(force: true)
        async let marketTask: () = marketplaceFeedService.listMarketplaceFeed(
            force: true
        )
        _ = await tripsTask

        if let ongoingTrip = tripService.ongoingTrips.first {
            let ongoingTripId = Int(ongoingTrip.id)
            // Sequential: the dayNumber→planDate conversion inside
            // fetchAllTripPlanItems needs the ONGOING trip loaded first.
            // Home shows today's plan pins, not expenses — TripDetailView
            // fetches expenses lazily when its History tab appears.
            await tripDetailService.loadTripDetail(
                tripId: ongoingTripId,
                force: true
            )
            await tripDetailService.fetchAllTripPlanItems(
                tripId: ongoingTripId,
                force: true
            )
        }

        _ = await marketTask
    }
}

private struct TripRequestAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    MainView(
        deepLinkTripId: .constant(nil),
        deepLinkChatTripId: .constant(nil)
    )
    .environment(UserProfileService())
    .environment(RealtimeService())
    .background(Constants.Background.ignoresSafeArea())
}
