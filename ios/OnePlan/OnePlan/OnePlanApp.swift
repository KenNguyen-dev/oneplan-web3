//
//  OnePlanApp.swift
//  OnePlan
//
//  Created by ken on 23/2/26.
//

import GoogleSignIn
import SwiftData
import SwiftUI
import UserNotifications

@main
struct OnePlanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var pendingFriendCode: String?
    @State private var pendingFriendRequest: FriendRequestDto?
    @State private var shouldPlayFriendRequestOpenSound = false
    @State private var deepLinkTripId: Int?
    @State private var deepLinkChatTripId: Int?
    @State private var deepLinkPlanItem: PlanItemDeepLink?
    @State private var deepLinkListingId: IdentifiableInt?
    @State private var userProfileService = UserProfileService()
    @State private var passportService = PassportService()
    @State private var realtimeService = RealtimeService()
    @State private var friendService = FriendService()
    @State private var authService = AuthService()
    @State private var storeManager = StoreManager()
    @State private var currencyCatalogService = CurrencyCatalogService.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var activeRootModal: RootModalRoute?
    @State private var isDismissingRootModal = false
    @State private var showSplash = true
    @State private var onboardingManager = OnboardingManager()
    @State private var tripWalletWelcomeManager = TripWalletWelcomeManager()
    @State private var showFreeTrial = false
    @State private var updateAppInfo: VersionCheckManager.ReturnResult?

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Constants.Background.ignoresSafeArea()

                if !onboardingManager.hasSeenOnboarding {
                    OnboardingView {
                        onboardingManager.completeOnboarding()
                    }
                } else if authService.isAuthenticated {
                    MainView(
                        deepLinkTripId: $deepLinkTripId,
                        deepLinkChatTripId: $deepLinkChatTripId,
                        deepLinkPlanItem: $deepLinkPlanItem,
                        deepLinkListingId: $deepLinkListingId,
                        onScannedFriendCode: { code in
                            pendingFriendCode = code
                            presentNextRootModalIfNeeded()
                        }
                    )
                        .task {
                            await currencyCatalogService.loadCurrencies()
                            await userProfileService.fetchProfile()
                            await storeManager.refreshSubscriptionStatus()
                            presentTripWalletWelcomeIfNeeded()
                            await presentFreeTrialIfEligible()
                            await passportService.fetchSummary()
                            await reportAppLaunchForCredits()
                            await registerForPushNotifications()
                            await AppBadgeService.shared.clearBadge()
                            realtimeService.connectSocket()
                            await checkPendingFriendRequests()
                            await realtimeService.refreshPendingTripInvites()
                            consumePendingChatDeepLinkIfNeeded()
                            consumePendingTripDetailDeepLinkIfNeeded()
                            consumePendingTripInviteDeepLinkIfNeeded()
                            consumePendingFriendRequestTapIfNeeded()
                            consumePendingPlanItemDeepLinkIfNeeded()
                            consumePendingListingDeepLinkIfNeeded()
                            presentNextRootModalIfNeeded()
                        }
                        .onChange(of: realtimeService.latestFriendRequest) { _, newRequest in
                            if let request = newRequest {
                                let isAlreadyPresented: Bool = {
                                    if case .receiveFriendRequest(let active) = activeRootModal,
                                       active.id == request.id {
                                        return true
                                    }
                                    return false
                                }()
                                if !isAlreadyPresented {
                                    pendingFriendRequest = request
                                    shouldPlayFriendRequestOpenSound = true
                                    presentNextRootModalIfNeeded()
                                }
                                realtimeService.latestFriendRequest = nil
                            }
                        }
                        .onChange(
                            of: realtimeService.activeTripInvitePresentation?.id
                        ) { _, _ in
                            presentNextRootModalIfNeeded()
                        }
                        .onChange(of: pendingFriendCode) { _, _ in
                            presentNextRootModalIfNeeded()
                        }
                        .onChange(of: pendingFriendRequest?.id) { _, _ in
                            presentNextRootModalIfNeeded()
                        }
                        .fullScreenCover(
                            item: $activeRootModal,
                            onDismiss: {
                                isDismissingRootModal = false
                                presentNextRootModalIfNeeded()
                            }
                        ) { route in
                            rootModalView(for: route)
                        }
                } else {
                    LoginView()
                }

                if showSplash {
                    SplashScreenView {
                        showSplash = false
                    }
                }
            }
            // Attached on the ZStack (not MainView) so it never collides with
            // the MainView-level root-modal fullScreenCover. MUST come BEFORE
            // the .environment(...) chain below so those injections wrap the
            // presented FreeTrialView — it reads StoreManager via @Environment,
            // and environment flows down into the cover only when the cover is a
            // descendant of the injection. Mutually gated with activeRootModal
            // via presentFreeTrialIfEligible / presentNextRootModalIfNeeded.
            .sheet(isPresented: Bindable(tripWalletWelcomeManager).isPresented) {
                WelcomeTripWalletView(
                    onContinue: {
                        tripWalletWelcomeManager.complete(
                            userId: tripWalletWelcomeUserId
                        )
                        Task { await presentFreeTrialIfEligible() }
                    },
                    onAddMoney: {
                        tripWalletWelcomeManager.complete(
                            userId: tripWalletWelcomeUserId
                        )
                        // Let the welcome sheet finish dismissing before we
                        // push Profile → wallet → deposit.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            NotificationCenter.default.post(
                                name: .openOnePlanWallet,
                                object: nil,
                                userInfo: ["openDeposit": true]
                            )
                        }
                    },
                    onClose: {
                        tripWalletWelcomeManager.complete(
                            userId: tripWalletWelcomeUserId
                        )
                        Task { await presentFreeTrialIfEligible() }
                    }
                )
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
            }
            .fullScreenCover(isPresented: $showFreeTrial) {
                // Read the deadline from the observable (set by
                // startTrialOfferWindowIfNeeded before showFreeTrial flips true),
                // NOT a parallel @State — a separate @State can lag behind the
                // present flag and make expiryDate default to now, instant-closing.
                FreeTrialView(
                    expiryDate: onboardingManager.trialOfferDeadline ?? Date(),
                    onClose: { showFreeTrial = false }
                )
            }
            .environment(userProfileService)
            .environment(passportService)
            .environment(realtimeService)
            .environment(authService)
            .environment(storeManager)
            .environment(networkMonitor)
            // Hard version gate: presented above everything (onboarding, login,
            // main, splash) the instant the installed build is behind the App
            // Store. No dismiss affordance — the only way out is updating. Mutually
            // gated with showFreeTrial / activeRootModal so two covers never race.
            .fullScreenCover(item: $updateAppInfo) { info in
                UpdateRequiredView(appInfo: info)
            }
            .onAppear {
                authService.configureGoogleSignIn()
                networkMonitor.start()
            }
            .task { await authService.checkAppleCredentialState() }
            .task {
                // Runs at launch regardless of auth state. Returns non-nil only
                // when behind the App Store version (fails open on any error).
                if let result = await VersionCheckManager.shared.checkIfAppUpdateAvailable() {
                    updateAppInfo = result
                }
            }
            .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                if !isAuthenticated {
                    userProfileService.reset()
                    passportService.reset()
                    friendService.reset()
                    storeManager.resetEntitlementState()
                    realtimeService.disconnectSocket()
                    tripWalletWelcomeManager.isPresented = false
                    Task {
                        await AppBadgeService.shared.clearBadge()
                    }
                    // Privacy: drop the offline trip cache (financial data) on logout.
                    Task {
                        await OngoingTripCache.shared.clearAll()
                    }
                    activeRootModal = nil
                    isDismissingRootModal = false
                    showFreeTrial = false
                    pendingFriendCode = nil
                    pendingFriendRequest = nil
                    deepLinkChatTripId = nil
                    deepLinkTripId = nil
                    deepLinkPlanItem = nil
                    deepLinkListingId = nil
                } else {
                    Task {
                        await storeManager.refreshSubscriptionStatus()
                    }
                    consumePendingChatDeepLinkIfNeeded()
                    consumePendingTripDetailDeepLinkIfNeeded()
                    consumePendingListingDeepLinkIfNeeded()
                    presentNextRootModalIfNeeded()
                }
            }
            .onChange(of: networkMonitor.isOnline) { wasOnline, isOnline in
                // Came back online → re-run the launch fetches that fail silently
                // while offline (profile/passport/currency/subscription, pending
                // invites). The shared services update everywhere they're read
                // (e.g. the Home header avatar). .task does not re-run on reconnect.
                guard !wasOnline, isOnline, authService.isAuthenticated else { return }
                Task { await userProfileService.fetchProfile(force: true) }
                Task { await passportService.fetchSummary(force: true) }
                Task { await currencyCatalogService.loadCurrencies() }
                Task { await storeManager.refreshSubscriptionStatus() }
                Task { await checkPendingFriendRequests() }
                Task { await realtimeService.refreshPendingTripInvites() }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification
                )
            ) { _ in
                Task {
                    await AppBadgeService.shared.clearBadge()
                }
                AnalyticsClient.shared.appDidBecomeActive()
                guard authService.isAuthenticated else { return }
                Task {
                    await storeManager.refreshSubscriptionStatus(silent: true)
                }
                // Fallback for the Share Extension: if the extension wrote a link
                // but its open() didn't foreground us (or we cold-launched), pick
                // it up here. Single-shot via consume(), so it won't double-queue
                // with the .onOpenURL path.
                consumeSharedExtractionURLIfNeeded()
                consumePendingChatDeepLinkIfNeeded()
                consumePendingTripDetailDeepLinkIfNeeded()
                consumePendingPlanItemDeepLinkIfNeeded()
                consumePendingListingDeepLinkIfNeeded()
                presentNextRootModalIfNeeded()
                Task {
                    await realtimeService.refreshPendingTripInvites()
                    consumePendingTripInviteDeepLinkIfNeeded()
                    presentNextRootModalIfNeeded()
                }
                Task {
                    await checkPendingFriendRequests()
                    consumePendingFriendRequestTapIfNeeded()
                    presentNextRootModalIfNeeded()
                }
            }
            .task { await TripImageCache.shared.clearExpired() }
            .preferredColorScheme(.light)
            .background(Constants.Background.ignoresSafeArea())
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                handleIncomingURL(url)
            }
        }
        .modelContainer(sharedModelContainer)
    }

    private func registerForPushNotifications() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {
            print("Notification authorization failed: \(error)")
        }
    }

    /// Reports the running app version to the server on launch so it can grant
    /// the per-version app-update scan-credit reward. Best-effort and silent:
    /// the server is idempotent per (user, version), so pinging every launch is
    /// safe. On success we post `.scanCreditBalanceChanged` so the Board badge
    /// reflects any newly granted credits.
    private func reportAppLaunchForCredits() async {
        guard
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            !version.isEmpty
        else { return }
        do {
            let response = try await APIClient.shared.reportAppLaunch(
                .init(body: .json(.init(appVersion: version)))
            )
            if case .ok = response {
                NotificationCenter.default.post(
                    name: .scanCreditBalanceChanged, object: nil
                )
            }
        } catch {
            // Best-effort: ignore transient/offline failures; the next cold
            // launch retries and the grant stays idempotent server-side.
        }
    }

    private func checkPendingFriendRequests() async {
        await friendService.loadPendingRequests()
        guard let first = friendService.pendingRequests.first else { return }

        if case .receiveFriendRequest(let active) = activeRootModal,
           active.id == first.id {
            return
        }
        if let existing = pendingFriendRequest, existing.id == first.id {
            return
        }
        pendingFriendRequest = first
    }

    @MainActor
    private func consumePendingFriendRequestTapIfNeeded() {
        guard DeepLinkRouter.shared.consumePendingFriendRequestTap() else {
            return
        }
        // Tap routing relies on checkPendingFriendRequests having populated
        // pendingFriendRequest; presentNextRootModalIfNeeded will then surface
        // the modal. No additional state change needed here.
    }

    @ViewBuilder
    private func rootModalView(for route: RootModalRoute) -> some View {
        switch route {
        case .sendFriendRequest(let friendCode):
            SendFriendRequestView(
                friendCode: friendCode,
                onDismiss: {
                    pendingFriendCode = nil
                    dismissActiveRootModal()
                }
            )
            .interactiveDismissDisabled()

        case .receiveFriendRequest(let request):
            ReceiveFriendRequestView(
                requestId: request.id,
                senderName: request.sender.displayName,
                senderAvatarUrl: request.sender.avatarUrl,
                mutualFriendCount: request.mutualFriendCount,
                onAccept: {
                    Task {
                        try? await friendService.respondToRequest(
                            id: request.id,
                            accept: true
                        )
                    }
                    pendingFriendRequest = nil
                    dismissActiveRootModal()
                },
                onDismiss: {
                    pendingFriendRequest = nil
                    dismissActiveRootModal()
                }
            )
            .interactiveDismissDisabled()
            .onAppear {
                if shouldPlayFriendRequestOpenSound {
                    SheetOpeningSoundPlayer.shared.play()
                    shouldPlayFriendRequestOpenSound = false
                }
            }

        case .tripInvite(let presentation):
            TripInvitationView(
                inviteCode: presentation.invite.inviteCode,
                onJoined: { tripId in
                    SheetOpeningSoundPlayer.shared.playNavigateFromSheet()
                    realtimeService.resolveTripInvite(
                        inviteCode: presentation.invite.inviteCode
                    )
                    dismissActiveRootModal()
                    NotificationCenter.default.post(
                        name: .tripCreated,
                        object: nil,
                        userInfo: ["tripId": tripId]
                    )
                },
                onDismiss: {
                    realtimeService.dismissActiveTripInvite()
                    dismissActiveRootModal()
                }
            )
            .interactiveDismissDisabled()
            .onAppear {
                if realtimeService.shouldPlayTripInviteOpenSound {
                    SheetOpeningSoundPlayer.shared.play()
                    realtimeService.shouldPlayTripInviteOpenSound = false
                }
            }
        }
    }

    /// Present the limited-time 1-month free-trial promo to an authenticated,
    /// trial-eligible, non-Pro user. Re-shows on later launches (once per
    /// session — this runs from the MainView .task) until the user buys or the
    /// persisted promo window elapses. The window's clock starts only here, at
    /// the first real presentation, so ineligible/Pro users (and transient
    /// product-load failures) never start it. Skipped if a root modal is up.
    @MainActor
    private func presentFreeTrialIfEligible() async {
        guard updateAppInfo == nil else { return }
        guard !tripWalletWelcomeManager.isPresented else { return }
        guard activeRootModal == nil, !showFreeTrial else { return }
        guard await storeManager.isEligibleForFreeTrial() else { return }
        // Re-check after the await: state may have changed while suspended.
        guard !tripWalletWelcomeManager.isPresented else { return }
        guard activeRootModal == nil, !showFreeTrial else { return }
        let deadline = onboardingManager.startTrialOfferWindowIfNeeded()
        guard Date() < deadline else { return }
        showFreeTrial = true
    }

    private var tripWalletWelcomeUserId: String? {
        userProfileService.profile.map { String($0.id) }
    }

    /// Show trip-wallet welcome once per user while logged in.
    private func presentTripWalletWelcomeIfNeeded() {
        guard updateAppInfo == nil else { return }
        guard activeRootModal == nil, !showFreeTrial else { return }
        tripWalletWelcomeManager.presentIfNeeded(
            userId: tripWalletWelcomeUserId,
            walletConfigured: true
        )
    }

    private func presentNextRootModalIfNeeded() {
        guard updateAppInfo == nil else { return }
        guard !tripWalletWelcomeManager.isPresented else { return }
        guard !showFreeTrial else { return }
        guard authService.isAuthenticated, activeRootModal == nil, !isDismissingRootModal else { return }

        if let pendingFriendCode {
            activeRootModal = .sendFriendRequest(friendCode: pendingFriendCode)
            return
        }

        if let pendingFriendRequest {
            activeRootModal = .receiveFriendRequest(request: pendingFriendRequest)
            return
        }

        if let presentation = realtimeService.activeTripInvitePresentation {
            activeRootModal = .tripInvite(presentation: presentation)
        }
    }

    private func dismissActiveRootModal() {
        guard activeRootModal != nil else { return }
        isDismissingRootModal = true
        activeRootModal = nil
    }

    private func handleIncomingURL(_ url: URL) {
        // Google Sign-In OAuth callback MUST be checked first — it uses the
        // reverse-client-id scheme (com.googleusercontent.apps.…) that the
        // invite parsers would otherwise ignore, but the contract is "short
        // circuit before anything else looks at the URL."
        if authService.handleURL(url) { return }

        if let code = parseInviteCode(from: url) {
            realtimeService.receiveTripInvite(
                inviteCode: code,
                tripName: String(localized: "Trip Invitation", comment: "Fallback title for a deep-linked trip invite with no trip name"),
                coverImageUrl: nil,
                invitedByDisplayName: "",
                source: .deepLink
            )
            return
        }
        // Share Extension hand-off: oneplan://board/extract carries no payload in
        // the URL itself — the shared IG/TikTok link lives in the App Group store
        // (single-shot via consume()). Queue it for BoardView to pick up.
        if isBoardExtractDeepLink(url) {
            consumeSharedExtractionURLIfNeeded()
            return
        }
        if let code = parseFriendCode(from: url) {
            pendingFriendCode = code
            presentNextRootModalIfNeeded()
            return
        }
        if let listingId = parseListingId(from: url) {
            // Reuses the existing Int-based listing deep-link pipeline (the same
            // one push notifications feed). Queue durably on the router, then
            // drain immediately for the warm/authenticated case; cold-launch and
            // logged-out→login are covered by the .task / didBecomeActive /
            // isAuthenticated consumers.
            DeepLinkRouter.shared.queueListingId(listingId)
            consumePendingListingDeepLinkIfNeeded()
            return
        }
    }

    /// True for `oneplan://board/extract` (the Share Extension's open URL). Does
    /// NOT reuse `extractCode`, which matches single-segment `host == path`
    /// links; here host is `board` and the trailing path segment is `extract`.
    private func isBoardExtractDeepLink(_ url: URL) -> Bool {
        url.scheme == DeepLinkBuilder.customScheme
            && url.host == "board"
            && url.pathComponents.last == "extract"
    }

    /// Reads the pending shared link from the App Group (single-shot) and queues
    /// it on the router. Used by BOTH the `oneplan://board/extract` deep-link
    /// path and the didBecomeActive fallback (covers cold launch / a failed
    /// extension open). `consume()` clears the store, so only the first caller
    /// queues — the other gets nil.
    @MainActor
    private func consumeSharedExtractionURLIfNeeded() {
        guard let link = SharedExtractionStore.consume() else { return }
        DeepLinkRouter.shared.queuePinExtractionURL(link)
    }

    private func parseInviteCode(from url: URL) -> String? {
        extractCode(from: url, path: DeepLinkBuilder.joinPath)
    }

    private func parseFriendCode(from url: URL) -> String? {
        extractCode(from: url, path: DeepLinkBuilder.friendPath)
    }

    /// Extracts a numeric listing id from `oneplan://listing/{id}` or
    /// `https://{universalLinkHost}/listing/{id}`. A dedicated parser (not
    /// `extractCode`) is required because `isValidDeepLinkCode` enforces a
    /// 6–64-char alphanumeric code, which short numeric ids fail; `Int()`
    /// parsing is inherently safe against crafted payloads.
    private func parseListingId(from url: URL) -> Int? {
        let segments = url.pathComponents.filter { $0 != "/" }

        let candidate: String?
        if url.scheme == DeepLinkBuilder.customScheme,
           url.host == DeepLinkBuilder.listingPath {
            candidate = segments.first
        } else if let host = url.host?.lowercased(),
                  DeepLinkBuilder.universalLinkHosts.contains(host),
                  segments.first == DeepLinkBuilder.listingPath {
            candidate = segments.dropFirst().first
        } else {
            candidate = nil
        }

        guard let raw = candidate, let id = Int(raw), id > 0 else { return nil }
        return id
    }

    /// Extracts the code segment from either `oneplan://{path}/{code}` or
    /// `https://{universalLinkHost}/{path}/{code}`.
    private func extractCode(from url: URL, path: String) -> String? {
        let segments = url.pathComponents.filter { $0 != "/" }

        let candidate: String?
        if url.scheme == DeepLinkBuilder.customScheme, url.host == path {
            candidate = segments.first.flatMap { $0.isEmpty ? nil : $0 }
        } else if let host = url.host?.lowercased(),
                  DeepLinkBuilder.universalLinkHosts.contains(host),
                  segments.first == path,
                  let code = segments.dropFirst().first,
                  !code.isEmpty {
            candidate = code
        } else {
            candidate = nil
        }

        guard let code = candidate, Self.isValidDeepLinkCode(code) else {
            return nil
        }
        return code
    }

    /// Defense-in-depth: deep-link payloads come from outside the app and
    /// could be crafted (phishing links, malicious QR codes, etc.). Restrict
    /// to a small alphanumeric charset within a reasonable length window
    /// before any routing decision. The server applies its own validation,
    /// but bouncing junk here avoids unnecessary API calls.
    private static func isValidDeepLinkCode(_ code: String) -> Bool {
        guard (6...64).contains(code.count) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return code.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    @MainActor
    private func consumePendingChatDeepLinkIfNeeded() {
        guard let tripId = DeepLinkRouter.shared.consumePendingChatTripId() else {
            return
        }
        deepLinkChatTripId = tripId
    }

    @MainActor
    private func consumePendingTripDetailDeepLinkIfNeeded() {
        guard let tripId = DeepLinkRouter.shared.consumePendingTripDetailId() else {
            return
        }
        deepLinkTripId = tripId
    }

    @MainActor
    private func consumePendingPlanItemDeepLinkIfNeeded() {
        guard let plan = DeepLinkRouter.shared.consumePendingPlanItem() else {
            return
        }
        deepLinkPlanItem = plan
    }

    @MainActor
    private func consumePendingListingDeepLinkIfNeeded() {
        guard let listingId = DeepLinkRouter.shared.consumePendingListingId() else {
            return
        }
        deepLinkListingId = IdentifiableInt(id: listingId)
    }

    @MainActor
    private func consumePendingTripInviteDeepLinkIfNeeded() {
        guard let inviteCode = DeepLinkRouter.shared.consumePendingTripInviteCode() else {
            return
        }
        if let invite = realtimeService.pendingTripInvites.first(where: {
            $0.inviteCode == inviteCode
        }) {
            realtimeService.receiveTripInvite(
                inviteCode: invite.inviteCode,
                tripName: invite.tripName,
                coverImageUrl: invite.coverImageUrl,
                invitedByDisplayName: invite.invitedByDisplayName,
                source: .api
            )
        } else {
            // Push arrived before refresh resolved the full payload — surface a
            // placeholder so the modal still presents; the next refresh will
            // overwrite the entry with full details.
            realtimeService.receiveTripInvite(
                inviteCode: inviteCode,
                tripName: String(localized: "Trip Invitation", comment: "Fallback title for a deep-linked trip invite with no trip name"),
                coverImageUrl: nil,
                invitedByDisplayName: "",
                source: .api
            )
        }
    }
}

private enum RootModalRoute: Identifiable {
    case sendFriendRequest(friendCode: String)
    case receiveFriendRequest(request: FriendRequestDto)
    case tripInvite(presentation: RealtimeService.TripInvitePresentation)

    var id: String {
        switch self {
        case .sendFriendRequest(let friendCode):
            "send-friend-\(friendCode)"
        case .receiveFriendRequest(let request):
            "receive-friend-\(request.id)"
        case .tripInvite(let presentation):
            "trip-invite-\(presentation.id.uuidString)"
        }
    }
}

// MARK: - Identifiable wrapper for String bindings with fullScreenCover(item:)

struct IdentifiableString: Identifiable {
    let id: String
    var value: String { id }
}

struct IdentifiableInt: Identifiable, Hashable {
    let id: Int
}

extension Binding where Value == String? {
    var identifiable: Binding<IdentifiableString?> {
        Binding<IdentifiableString?>(
            get: { self.wrappedValue.map { IdentifiableString(id: $0) } },
            set: { self.wrappedValue = $0?.id }
        )
    }
}

extension Binding where Value == Int? {
    var identifiable: Binding<IdentifiableInt?> {
        Binding<IdentifiableInt?>(
            get: { self.wrappedValue.map { IdentifiableInt(id: $0) } },
            set: { self.wrappedValue = $0?.id }
        )
    }
}
