//
//  TripView.swift
//  OnePlan
//
//  Created by ken on 25/2/26.
//

import MapKit
import PhotosUI
import SwiftUI

private struct SelectedPlanRoute: Hashable {
    let id: Int
    let planItem: PlanItemDto

    static func == (lhs: SelectedPlanRoute, rhs: SelectedPlanRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct SelectedDayMap: Hashable {
    let id: Int
    let dayLabel: String
    let pins: [PlanDayPin]
    let routeLegs: [PlanDayRouteLeg]

    static func == (lhs: SelectedDayMap, rhs: SelectedDayMap) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct TripDetailView: View {
    @Environment(UserProfileService.self) private var userProfileService
    @Environment(StoreManager.self) private var storeManager
    @Environment(RealtimeService.self) private var realtimeService
    @Environment(NetworkMonitor.self) private var networkMonitor
    // Reading @Environment(\.dismiss) directly here caused an iOS-<26 infinite
    // re-render loop (NavigationStack relayout churns \.dismiss's identity →
    // this heavy host re-renders → rebuilds destinations → relayout → …). Route
    // dismissal through StableDismiss, which lives off the dependency graph.
    @State private var stableDismiss = StableDismiss()
    let trip: TripDto?
    let initialBudgetId: Int?
    let initialExpenseId: Int?
    let initialPlanItemId: Int?
    @State private var selectedTab: TripTab = .history
    @State private var service = TripDetailService()
    @State private var friendService = FriendService()
    @State private var noteService = NoteService()
    @State private var tripIdOverride: Int?
    @State private var isAddingBudget = false
    @State private var isAddingExpense = false
    @State private var pendingBudgetName = ""
    @State private var pendingBudgetAmount: Double = 0
    @State private var pendingBudgetCurrency: Currency? = nil
    @State private var pendingExpenseName = ""
    @State private var pendingExpenseAmount: Double = 0
    @State private var pendingExpenseCurrency: Currency? = nil
    @State private var pendingExpenseCategory: String = "FOOD"
    @State private var pendingExpenseMemberIds: [Int] = []
    @State private var expenseFormResetToken = 0
    @State private var selectedBudgetId: Int?
    @State private var selectedExpenseId: Int?
    @State private var isShowingEndTrip = false
    @State private var isShowingInvite = false
    @State private var isShowingLeaveConfirm = false
    @State private var isShowingLeaveSheet = false
    /// Leave → Contribute handoff: set before dismissing leave, posted in onDismiss
    /// so UIKit is not still tearing down the leave sheet (drops the deposit sheet).
    @State private var pendingLeaveContributeMicro: UInt64?
    @State private var isAnnouncingLeave = false
    @State private var leaveAnnounceError: String?
    @State private var leaveConfirmError: String?
    @State private var isConfirmingVaultLeave = false
    @State private var hostLeaveRequest: Components.Schemas.VaultLeaveRequestDto?
    @State private var vaultLeaveRequestsByUserId: [Int: Components.Schemas.VaultLeaveRequestDto] = [:]
    /// Session suppress after host dismisses without confirming (Members menu still works).
    @State private var dismissedHostLeaveUserIds: Set<Int> = []
    /// Host confirm leave — brief confirmation after the sheet dismisses.
    @State private var memberLeftToast: String?
    @State private var leaveSettlement: LeaveSettlementDto?
    @State private var navigateToLeaveSettlement = false
    @State private var isShowingCreatePlan = false
    @State private var createPlanDate: String = ""
    @State private var createPlanDayNumber: Int?
    // PlanFormView copies PlanFormModel into @State in its init; without a
    // fresh identity per presentation the old @State storage is reused and
    // stale form data reappears (same issue as expenseFormResetToken).
    @State private var createPlanFormToken = 0
    @State private var selectedPlanRoute: SelectedPlanRoute?
    @State private var selectedDayMap: SelectedDayMap?
    @State private var isShowingStartTripSheet = false
    @State private var pendingStartDate: Date = Date()
    @State private var pendingEndDate: Date? = nil
    @State private var isShowingTripDatesSheet = false
    @State private var pendingScheduleConfirmStart: Date? = nil
    @State private var pendingScheduleConfirmEnd: Date? = nil
    @State private var scheduleShrinkLostCount: Int = 0
    @State private var isShowingScheduleShrinkConfirm = false
    @State private var isShowingStartTripAlert = false
    @State private var startTripAlertMessage = ""
    @State private var isShowingEndTripConfirm = false
    @State private var endTripErrorMessage = ""
    @State private var isShowingEndTripError = false
    @State private var isShowingDeleteTripConfirm = false
    @State private var deleteTripErrorMessage = ""
    @State private var isShowingDeleteTripError = false
    @State private var hasHandledInitialHistoryRoute = false
    /// Resolved once on appear. Trips created before the group wallet existed
    /// have no vault, which is the ordinary case rather than an error.
    @State private var hasVault = false
    @State private var isEndApprovalPending = false
    @State private var endConsensusRequest: TripEndRequestDto?
    @State private var isShowingEndReview = false
    @State private var isShowingEndWaiting = false
    @State private var isShowingEndDenied = false
    @State private var isShowingScanBill = false
    @State private var showingAIPaywall = false
    @State private var isShowingInsightPaywall = false
    @State private var lastNonInsightTab: TripTab = .history
    @State private var pendingFriendCode: String?
    @State private var selectedMemberUserId: Int?
    @State private var isShowingGallery = false
    @State private var isPresentingGroupCurrencySheet: Bool = false
    @State private var isPresentingLocalCurrencySheet: Bool = false
    @State private var pendingGroupCurrency: Currency? = nil
    @State private var pendingLocalCurrency: Currency? = nil
    @State private var isShowingCurrencyLockedAlert = false
    @State private var isShowingRearrangeSheet = false
    @State private var rearrangeMode: TripPlanRearrangeMode = .days
    @State private var isShowingTripDeletedAlert = false

    init(trip: TripDto? = nil, tripDetailService: TripDetailService? = nil) {
        self.trip = trip
        self.initialBudgetId = nil
        self.initialExpenseId = nil
        self.initialPlanItemId = nil
        if let tripDetailService {
            self._service = State(initialValue: tripDetailService)
        }
    }

    init(
        tripId: Int,
        initialBudgetId: Int? = nil,
        initialExpenseId: Int? = nil,
        initialPlanItemId: Int? = nil,
        initialAddExpense: Bool = false,
        initialTab: TripTab? = nil,
        tripDetailService: TripDetailService? = nil
    ) {
        self.trip = nil
        self._tripIdOverride = State(initialValue: tripId)
        self.initialBudgetId = initialBudgetId
        self.initialExpenseId = initialExpenseId
        self.initialPlanItemId = initialPlanItemId
        self._isAddingExpense = State(initialValue: initialAddExpense)
        if let initialTab {
            self._selectedTab = State(initialValue: initialTab)
        }
        if let tripDetailService {
            self._service = State(initialValue: tripDetailService)
        }
    }

    private var tripId: Int? { tripIdOverride ?? trip?.id }

    private var isCreator: Bool {
        guard let userId = userProfileService.profile?.id,
            let createdById = service.trip?.createdById ?? trip?.createdById
        else {
            return false
        }
        return userId == createdById
    }

    private var isPlanningTrip: Bool {
        let status = service.trip?.status.value1 ?? trip?.status.value1
        return status == .PLANNING
    }

    private var isOngoingTrip: Bool {
        let status = service.trip?.status.value1 ?? trip?.status.value1
        return status == .ONGOING
    }

    private var allowsFinancialActions: Bool {
        isPlanningTrip || isOngoingTrip
    }

    /// Offline mode is read-only. Gate every *write* affordance on this — but
    /// NOT the `isOngoingTrip`/`isPlanningTrip` computeds, which also drive
    /// read-side rendering (rearrange mode, plan-date strings).
    private var isOffline: Bool {
        !networkMonitor.isOnline || service.isServingCachedData
    }

    private var canEdit: Bool {
        allowsFinancialActions && !isOffline
    }

    // `body` was a single ~960-line expression the type-checker could not
    // solve in reasonable time. It is staged through the helpers below so each
    // modifier chain type-checks independently — the order is unchanged.
    var body: some View {
        tripDetailRoot
            .sheet(item: $hostLeaveRequest) { request in
                VaultLeaveHostBottomSheet(
                    request: request,
                    isWorking: isConfirmingVaultLeave,
                    onConfirm: {
                        guard let tripId else { return false }
                        isConfirmingVaultLeave = true
                        let leavingName = request.displayName
                        let leavingUserId = request.userId
                        let ok = await service.confirmVaultLeave(
                            tripId: tripId,
                            userId: leavingUserId
                        )
                        isConfirmingVaultLeave = false
                        if ok {
                            dismissedHostLeaveUserIds.remove(leavingUserId)
                            vaultLeaveRequestsByUserId.removeValue(forKey: leavingUserId)
                            hostLeaveRequest = nil
                            showMemberLeftToast(leavingName)
                            Task {
                                await refreshVaultLeaveRequests(
                                    tripId: tripId,
                                    presentSheet: false
                                )
                                await service.loadTripDetail(tripId: tripId, force: true)
                                await service.fetchExpenses(tripId: tripId, force: true)
                            }
                        } else {
                            leaveConfirmError =
                                service.error
                                ?? String(localized: "Failed to confirm leave")
                        }
                        return ok
                    }
                )
                .id("\(request.userId)-\(request.status)-\(request.announcedNetMicro)")
                .onDisappear {
                    if vaultLeaveRequestsByUserId[request.userId] != nil {
                        dismissedHostLeaveUserIds.insert(request.userId)
                    }
                }
            }
            .overlay(alignment: .top) {
                if let memberLeftToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                        Text(memberLeftToast)
                            .font(Font.beVietnamPro(15))
                            .tracking(-0.3)
                    }
                    .foregroundStyle(Constants.White)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Constants.Neutral900.opacity(0.92), in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .animation(.snappy(duration: 0.25), value: memberLeftToast)
            .alert(
                String(localized: "Could not confirm leave"),
                isPresented: Binding(
                    get: { leaveConfirmError != nil },
                    set: { if !$0 { leaveConfirmError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { leaveConfirmError = nil }
            } message: {
                Text(leaveConfirmError ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .vaultBalanceChanged)) { _ in
                guard let tripId, hasVault else { return }
                Task {
                    await refreshVaultLeaveRequests(
                        tripId: tripId,
                        presentSheet: hostLeaveRequest == nil
                    )
                    if let current = hostLeaveRequest,
                       let updated = vaultLeaveRequestsByUserId[current.userId]
                    {
                        hostLeaveRequest = updated
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .vaultLeaveRequested)) {
                notification in
                guard
                    let currentTripId = tripId,
                    let updatedTripId = notification.userInfo?["tripId"] as? Int,
                    updatedTripId == currentTripId
                else { return }

                if let userId = notification.userInfo?["userId"] as? Int {
                    dismissedHostLeaveUserIds.remove(userId)
                }
                Task {
                    await refreshVaultLeaveRequests(
                        tripId: currentTripId,
                        presentSheet: true
                    )
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .vaultLeaveDepositCompleted)
            ) { notification in
                guard
                    let currentTripId = tripId,
                    (notification.object as? Int) == currentTripId
                else { return }
                Task { await autoAnnounceAfterLeaveDeposit(tripId: currentTripId) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tripMemberRemoved)) {
                notification in
                handleTripMemberRemovedNotification(notification)
            }
    }

    private var tripDetailRoot: some View {
        applyLifecycle(
            to: applyToolbar(
                to: applyModalsB(
                    to: applyModalsA(
                        to: applyPresentation(to: mainScrollView)))))
    }

    private var mainScrollView: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if isOffline {
                        OfflineBanner(cachedAt: service.cachedAt)
                            .padding(.bottom, 10)
                    }
                    // Vault card is always shown. The on-chain vault is created
                    // lazily on the first deposit — until then the balance is 0.
                    TripVaultSection(
                        tripId: tripId ?? 0,
                        tripName: service.trip?.name ?? trip?.name ?? "",
                        coverImageUrl: service.trip?.coverImageUrl
                            ?? trip?.coverImageUrl,
                        currency: Currency(from: service.trip?.currency.value1) ?? .VND,
                        members: service.trip?.members ?? trip?.members ?? [],
                        isWaitingForEndApproval: isEndApprovalPending,
                        needsEndTripReview: endConsensusRequest?.myDecision == nil
                            && isEndApprovalPending,
                        onWaitingForApproval: {
                            openEndConsensusFromCard()
                        }
                    )
                    if isAddingBudget {
                        TripHistorySection(
                            groupedHistory: service.groupedBudgetHistory,
                            isLoading: false,
                            onBudgetTapped: { budgetId in
                                selectedBudgetId = budgetId
                            },
                            onExpenseTapped: { expenseId in
                                guard !isOffline else { return }
                                selectedExpenseId = expenseId
                            }
                        )
                        .padding(.top, 12)
                        .transition(.opacity)
                    } else if isAddingExpense {
                        TripAddExpenseSection(
                            members: service.trip?.members ?? trip?.members
                                ?? [],
                            onCategoryChanged: { category in
                                pendingExpenseCategory = category.apiValue
                            },
                            onMembersChanged: { memberIds in
                                pendingExpenseMemberIds = memberIds
                            }
                        )
                        .id(expenseFormResetToken)
                        .padding(.top, 12)
                        .transition(.opacity)
                    } else {
                        VStack(spacing: 0) {
                            TripTabBar(
                                selectedTab: Binding(
                                    get: { selectedTab },
                                    set: { selectTripTab($0) }
                                ),
                                isEnabled: isOngoingTrip || isPlanningTrip
                            )
                            .padding(.top, 12)
                            tabContentView
                        }
                        .gesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { value in
                                    guard isOngoingTrip || isPlanningTrip else { return }
                                    let horizontal = value.translation.width
                                    let vertical = value.translation.height
                                    guard abs(horizontal) > abs(vertical) else { return }
                                    let allTabs = TripTab.allCases
                                    guard let currentIndex = allTabs.firstIndex(of: selectedTab) else { return }
                                    withAnimation(.snappy(duration: 0.25)) {
                                        if horizontal < 0, currentIndex < allTabs.count - 1 {
                                            selectTripTab(allTabs[currentIndex + 1])
                                        } else if horizontal > 0, currentIndex > 0 {
                                            selectTripTab(allTabs[currentIndex - 1])
                                        }
                                    }
                                }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isAddingBudget)
                .animation(.easeInOut(duration: 0.3), value: isAddingExpense)
                .onChange(of: isAddingBudget) { _, newValue in
                    if !newValue && !isAddingExpense {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                .onChange(of: isAddingExpense) { _, newValue in
                    if !newValue && !isAddingBudget {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                .frame(
                    minHeight: max(0, proxy.size.height - 20),
                    alignment: .top
                )
                .padding(10)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await refreshTripDetail()
            }
            .background(.clear)
        }
    }

    /// Full-screen covers, member sheet and navigation destinations.
    private func applyPresentation(to content: some View) -> some View {
        content
        .background(Constants.Background.ignoresSafeArea())
        .fullScreenCover(isPresented: $isShowingScanBill) {
            BillSplitFlowView(
                tripId: tripId ?? 0,
                members: service.trip?.members ?? trip?.members ?? [],
                groupCurrency: service.homeCurrency,
                localCurrency: service.primaryLocalCurrency,
                onDismiss: {
                    isShowingScanBill = false
                    isAddingExpense = false
                    if let tripId {
                        Task {
                            await service.fetchExpenses(
                                tripId: tripId,
                                force: true
                            )
                        }
                    }
                }
            )
        }
        .fullScreenCover(item: $pendingFriendCode.identifiable) { wrapper in
            SendFriendRequestView(
                friendCode: wrapper.value,
                onDismiss: {
                    pendingFriendCode = nil
                }
            )
        }
        .sheet(item: $selectedMemberUserId.identifiable) { wrapper in
            FriendProfileView(
                userId: wrapper.id,
                onDismiss: {
                    selectedMemberUserId = nil
                    // Refresh so a remove/add reflects in the member-row pill state.
                    Task { await friendService.loadFriends() }
                }
            )
        }
        .navigationDestination(isPresented: $isShowingEndTrip) {
            TripEndView(service: service, tripId: tripId ?? 0)
        }
        .navigationDestination(item: $selectedBudgetId) { _ in
            WhoDepositView(
                tripId: tripId ?? 0,
                service: service
            )
        }
        .navigationDestination(item: $selectedExpenseId) { expenseId in
            ExpenseDetailView(
                tripId: tripId ?? 0,
                expenseId: expenseId,
                allExpenseIds: service.expenseIds,
                service: service
            )
        }
        .navigationDestination(item: $selectedPlanRoute) { route in
            PlanDetailView(
                tripId: tripId ?? 0,
                planItem: route.planItem,
                siblingPlanItems: siblingPlanItems(for: route.planItem),
                service: service,
                members: service.trip?.members ?? trip?.members ?? []
            )
        }
        .navigationDestination(item: $selectedDayMap) { dayMap in
            PlanDayMapView(
                dayLabel: dayMap.dayLabel,
                pins: dayMap.pins,
                routeLegs: dayMap.routeLegs
            )
        }
        .navigationDestination(isPresented: $isShowingCreatePlan) {
            PlanFormView(
                form: PlanFormModel(
                    mode: .create,
                    tripId: tripId ?? 0,
                    members: service.trip?.members ?? trip?.members ?? [],
                    isPlanningMode: isPlanningTrip,
                    service: service,
                    tripStartDate: PlanFormDateParser.parseTripStartDate(service.trip?.startDate ?? trip?.startDate),
                    initialPlanDate: createPlanDate.isEmpty ? nil : createPlanDate,
                    initialDayNumber: createPlanDayNumber
                ),
                service: service
            )
            .id(createPlanFormToken)
        }
        .navigationDestination(isPresented: $isShowingGallery) {
            GalleryView(
                tripName: service.trip?.name ?? trip?.name ?? "",
                photos: service.photos,
                hasMore: service.hasMorePhotos,
                onLoadMore: {
                    guard let tripId else { return }
                    Task { await service.fetchMorePhotos(tripId: tripId) }
                },
                onDelete: { photo in
                    guard let tripId else { return }
                    Task { await service.deletePhoto(tripId: tripId, photoId: photo.id) }
                }
            )
        }
        .navigationDestination(isPresented: $isShowingInvite) {
            TripInviteView(
                tripId: tripId ?? 0,
                tripName: service.trip?.name ?? trip?.name ?? "",
                coverImageUrl: service.trip?.coverImageUrl
                    ?? trip?.coverImageUrl,
                inviteCode: service.trip?.inviteCode ?? "",
                members: service.trip?.members ?? trip?.members ?? []
            )
        }
        .navigationDestination(isPresented: $navigateToLeaveSettlement) {
            if let settlement = leaveSettlement {
                TripEndView(
                    service: service,
                    tripId: tripId ?? 0,
                    entryMode: .leavingMember(settlement: settlement)
                )
            }
        }
    }

    /// Paywalls, leave flow and the first batch of alerts.
    private func applyModalsA(to content: some View) -> some View {
        content
        .sheet(isPresented: $showingAIPaywall) {
            SubscriptionView()
        }
        .fullScreenCover(
            isPresented: $isShowingInsightPaywall,
            onDismiss: handleInsightPaywallDismissed
        ) {
            SubscriptionView(onClose: handleInsightPaywallClosed)
        }
        .sheet(
            isPresented: $isShowingLeaveSheet,
            onDismiss: {
                guard let micro = pendingLeaveContributeMicro else { return }
                pendingLeaveContributeMicro = nil
                guard let tripId else { return }
                // Leave settle amount on the service so Contribute cannot open
                // as a free keypad if Notification userInfo is dropped.
                TripVaultService.shared.pendingLeaveContributeMicro = micro
                // Next run loop: leave sheet must fully tear down first.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .vaultRequestContribute,
                        object: tripId,
                        userInfo: ["amountMicro": String(micro)]
                    )
                }
            }
        ) {
            if let preview = service.leavePreview {
                if preview.hasVault {
                    VaultLeaveBottomSheet(
                        preview: preview,
                        isWorking: isAnnouncingLeave,
                        onDeposit: {
                            let owed = UInt64(preview.owedMicro ?? "0") ?? 0
                            // Gross up for the 0.1% on-chain skim so vault nets `owed`.
                            let gross = ContributeToVaultView.grossDeposit(forNet: owed)
                            pendingLeaveContributeMicro = gross > 0 ? gross : nil
                            isShowingLeaveSheet = false
                        },
                        onAnnounce: {
                            guard let tripId else { return }
                            isAnnouncingLeave = true
                            defer { isAnnouncingLeave = false }
                            let ok = await service.announceVaultLeave(tripId: tripId)
                            if ok {
                                await refreshVaultLeaveRequests(tripId: tripId)
                            } else {
                                leaveAnnounceError =
                                    service.error
                                    ?? String(localized: "Failed to announce leave")
                            }
                        }
                    )
                    .id(preview.leaveRequestPending)
                } else {
                    LeaveTripBottomSheet(
                        preview: preview,
                        currency: Currency(from: service.trip?.currency.value1) ?? .VND,
                        isLeaving: service.isLeavingTrip,
                        onLeave: {
                            guard let tripId,
                                  let userId = userProfileService.profile?.id
                            else { return }
                            if let settlement = await service.leaveTrip(
                                tripId: tripId,
                                userId: userId
                            ) {
                                leaveSettlement = settlement
                                NotificationCenter.default.post(
                                    name: .tripLeft,
                                    object: nil
                                )
                                isShowingLeaveSheet = false
                                navigateToLeaveSettlement = true
                            }
                        }
                    )
                }
            }
        }
        .alert(
            String(localized: "Could not announce"),
            isPresented: Binding(
                get: { leaveAnnounceError != nil },
                set: { if !$0 { leaveAnnounceError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { leaveAnnounceError = nil }
        } message: {
            Text(leaveAnnounceError ?? "")
        }
        .alert("Leave trip?", isPresented: $isShowingLeaveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                guard let tripId,
                    let userId = userProfileService.profile?.id
                else { return }
                Task {
                    let settlement = await service.leaveTrip(
                        tripId: tripId,
                        userId: userId
                    )
                    if settlement != nil {
                        NotificationCenter.default.post(
                            name: .tripLeft,
                            object: nil
                        )
                        stableDismiss()
                    }
                }
            }
        } message: {
            Text(
                "You will no longer have access to this trip's plans, expenses, and photos."
            )
        }
        .alert("Can't start trip", isPresented: $isShowingStartTripAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startTripAlertMessage)
        }
        .alert(
            // Pluralized in the String Catalog by the count argument.
            "Removing days will delete \(scheduleShrinkLostCount) plans",
            isPresented: $isShowingScheduleShrinkConfirm
        ) {
            Button("Cancel", role: .cancel) {
                pendingScheduleConfirmStart = nil
                pendingScheduleConfirmEnd = nil
                scheduleShrinkLostCount = 0
            }
            Button("Remove", role: .destructive) {
                guard
                    let tripId,
                    let start = pendingScheduleConfirmStart,
                    let end = pendingScheduleConfirmEnd
                else { return }
                pendingScheduleConfirmStart = nil
                pendingScheduleConfirmEnd = nil
                scheduleShrinkLostCount = 0
                Task {
                    _ = await service.updateTripSchedule(
                        tripId: tripId,
                        startDate: start,
                        endDate: end
                    )
                }
            }
        } message: {
            Text("Plans on trailing days will be permanently removed.")
        }
    }

    /// Trip-date sheets, end/delete alerts and currency pickers.
    private func applyModalsB(to content: some View) -> some View {
        content
        .sheet(isPresented: $isShowingStartTripSheet) {
            StartTripBottomSheet(
                startDate: $pendingStartDate,
                endDate: $pendingEndDate,
                timeZone: .constant(.current),
                buttonTitle: String(localized: "Start trip"),
                minimumStartDate: nil,
                onStartTrip: {
                    guard !service.isStartingTrip else { return }
                    Task {
                        await startTripIfPossible(
                            startDate: pendingStartDate,
                            endDate: pendingEndDate ?? pendingStartDate
                        )
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $isShowingTripDatesSheet) {
            TripDatesBottomSheet(
                isPresented: $isShowingTripDatesSheet,
                initialStartDate: service.tripStartDate,
                initialEndDate: service.tripEndDate,
                minimumStartDate: nil,
                onConfirm: { start, end in
                    handleTripDatesConfirmed(start: start, end: end)
                }
            )
        }
        .alert("End trip?", isPresented: $isShowingEndTripConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End trip", role: .destructive) {
                guard let tripId else { return }
                Task {
                    if hasVault {
                        let result = await service.requestVaultEndConsensus(tripId: tripId)
                        switch result {
                        case .success(let request):
                            endConsensusRequest = request
                            isEndApprovalPending = request.status.value1 == .PENDING
                            if request.myDecision == nil {
                                isShowingEndReview = true
                            } else if request.status.value1 == .PENDING {
                                isShowingEndWaiting = true
                            } else if request.status.value1 == .APPROVED {
                                await presentEndedTrip(tripId: tripId)
                            }
                        case .failure(let message):
                            endTripErrorMessage = message
                            isShowingEndTripError = true
                        }
                    } else {
                        let result = await service.endTrip(tripId: tripId)
                        switch result {
                        case .success:
                            if service.photos.isEmpty {
                                await service.fetchPhotos(tripId: tripId)
                            }
                            NotificationCenter.default.post(
                                name: .tripStatusChanged,
                                object: nil
                            )
                            isShowingEndTrip = true
                        case .failure(let message):
                            endTripErrorMessage = message
                            isShowingEndTripError = true
                        }
                    }
                }
            }
        } message: {
            Text(
                hasVault
                    ? String(
                        localized: "All members must approve ending this trip. The trip stays ongoing until everyone agrees."
                    )
                    : String(
                        localized: "This will end the trip for all members. This action cannot be undone."
                    )
            )
        }
        .fullScreenCover(isPresented: $isShowingEndReview) {
            TripEndReviewView(
                tripId: tripId ?? 0,
                coverImageUrl: service.trip?.coverImageUrl
                    ?? trip?.coverImageUrl,
                onApproved: { request in
                    endConsensusRequest = request
                    isShowingEndReview = false
                    if request.status.value1 == .APPROVED {
                        Task { await presentEndedTrip(tripId: tripId ?? 0) }
                    } else {
                        isEndApprovalPending = true
                        isShowingEndWaiting = true
                    }
                },
                onDenied: { request in
                    endConsensusRequest = request
                    isEndApprovalPending = false
                    isShowingEndReview = false
                    isShowingEndDenied = true
                },
                onBack: {
                    isShowingEndReview = false
                }
            )
        }
        .fullScreenCover(isPresented: $isShowingEndWaiting) {
            if let request = endConsensusRequest {
                TripEndWaitingView(
                    tripId: tripId ?? 0,
                    request: request,
                    onBack: {
                        isShowingEndWaiting = false
                    },
                    onAllApproved: {
                        isShowingEndWaiting = false
                        isEndApprovalPending = false
                        Task { await presentEndedTrip(tripId: tripId ?? 0) }
                    },
                    onDenied: { denied in
                        endConsensusRequest = denied
                        isEndApprovalPending = false
                        isShowingEndWaiting = false
                        isShowingEndDenied = true
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $isShowingEndDenied) {
            if let request = endConsensusRequest {
                TripEndDeniedView(
                    request: request,
                    onDismiss: {
                        isShowingEndDenied = false
                        endConsensusRequest = nil
                        isEndApprovalPending = false
                    }
                )
            }
        }
        .alert("Failed to end trip", isPresented: $isShowingEndTripError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(endTripErrorMessage)
        }
        .alert("Delete trip?", isPresented: $isShowingDeleteTripConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let tripId, !service.isDeletingTrip else { return }
                Task {
                    let success = await service.deleteTrip(tripId: tripId)
                    if success {
                        NotificationCenter.default.post(
                            name: .tripLeft,
                            object: nil
                        )
                        stableDismiss()
                    } else {
                        deleteTripErrorMessage =
                            service.error ?? String(localized: "Failed to delete trip")
                        isShowingDeleteTripError = true
                    }
                }
            }
        } message: {
            Text(
                "This will permanently delete the trip for all members. This action cannot be undone."
            )
        }
        .alert("Failed to delete trip", isPresented: $isShowingDeleteTripError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteTripErrorMessage)
        }
        .alert("Trip deleted", isPresented: $isShowingTripDeletedAlert) {
            Button("OK", role: .cancel) {
                NotificationCenter.default.post(
                    name: .tripLeft,
                    object: nil
                )
                stableDismiss()
            }
        } message: {
            Text("This trip has been deleted by the owner.")
        }
        .alert("Can't change currency", isPresented: $isShowingCurrencyLockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This trip already has budgets or expenses. Delete them before changing currency.")
        }
        .sheet(isPresented: $isPresentingGroupCurrencySheet) {
            CurrencyPickerBottomSheet(
                selectedCurrency: $pendingGroupCurrency,
                showsNoneOption: false
            )
        }
        .sheet(isPresented: $isPresentingLocalCurrencySheet) {
            CurrencyPickerBottomSheet(
                selectedCurrency: $pendingLocalCurrency,
                showsNoneOption: true
            )
        }
        .sheet(isPresented: $isShowingRearrangeSheet) {
            RearrangeDateBottomSheet(
                items: rearrangeSheetItems,
                onRearrange: handleRearrange,
                onDelete: handleDeleteRearrangeItem
            )
        }
        .onChange(of: isPresentingGroupCurrencySheet) { _, newValue in
            // React on sheet close. The picker's Confirm button writes
            // pendingGroupCurrency first, then flips isPresented to false.
            // By the time this fires, pendingGroupCurrency reflects the final pick.
            guard !newValue,
                  let tripId,
                  let picked = pendingGroupCurrency,
                  picked != service.homeCurrency
            else { return }
            Task {
                _ = await service.updateTripHomeCurrency(tripId: tripId, currency: picked)
            }
        }
        .onChange(of: isPresentingLocalCurrencySheet) { _, newValue in
            // React on sheet close. nil pendingLocalCurrency means "None".
            guard !newValue, let tripId else { return }
            let currencies: [Currency] = pendingLocalCurrency.map { [$0] } ?? []
            guard currencies != service.localCurrencies else { return }
            Task {
                _ = await service.updateTripLocalCurrencies(tripId: tripId, currencies: currencies)
            }
        }
    }

    /// The top bar: back-button handling plus the three toolbar states.
    private func applyToolbar(to content: some View) -> some View {
        content
        .navigationBarBackButtonHidden(isAddingBudget || isAddingExpense)
        .toolbar {
            if isAddingBudget || isAddingExpense {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                        if isAddingBudget {
                            isAddingBudget = false
                            pendingBudgetName = ""
                            pendingBudgetAmount = 0
                            pendingBudgetCurrency = nil
                        }
                        if isAddingExpense {
                            isAddingExpense = false
                            pendingExpenseName = ""
                            pendingExpenseAmount = 0
                            pendingExpenseCurrency = nil
                            pendingExpenseCategory = "FOOD"
                            pendingExpenseMemberIds = []
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Constants.ContentB)
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isAddingBudget {
                    GlassContainerCompat(spacing: 8) {
                        if service.isCreatingBudget {
                            ProgressView()
                                .padding(.horizontal, 13)
                                .padding(.vertical, 11.5)
                        } else {
                            ToolbarIconButton(systemName: "checkmark") {
                                guard pendingBudgetAmount > 0, let tripId else {
                                    return
                                }
                                Task {
                                    let home = service.homeCurrency
                                    let picked = pendingBudgetCurrency
                                    let hasCurrencyChoice =
                                        service.displayCurrencies.count >= 2
                                    let isLocal =
                                        hasCurrencyChoice
                                        && picked != nil
                                        && picked != home
                                    let success = await service.createBudget(
                                        tripId: tripId,
                                        name: pendingBudgetName,
                                        amount: pendingBudgetAmount,
                                        originalAmount: isLocal
                                            ? pendingBudgetAmount
                                            : nil,
                                        originalCurrency: isLocal
                                            ? picked
                                            : nil
                                    )
                                    if success {
                                        UIApplication.shared.sendAction(
                                            #selector(
                                                UIResponder.resignFirstResponder
                                            ),
                                            to: nil,
                                            from: nil,
                                            for: nil
                                        )
                                        isAddingBudget = false
                                        pendingBudgetName = ""
                                        pendingBudgetAmount = 0
                                        pendingBudgetCurrency = nil
                                    }
                                }
                            }
                            .disabled(
                                pendingBudgetAmount <= 0
                                    || service.isCreatingBudget
                            )
                        }
                    }
                } else if isAddingExpense {
                    GlassContainerCompat(spacing: 0) {
                        // -16 overlaps the glass pills so they morph on iOS 26;
                        // below iOS 26 the opaque fallback pills would collide,
                        // so keep a positive gap there.
                        HStack(spacing: glassMorphSpacing(-16, fallback: 8)) {
                            Button {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                if storeManager.isPro {
                                    isShowingScanBill = true
                                } else {
                                    showingAIPaywall = true
                                }
                            } label: {
                                Text("Scan by AI")
                                    .font(
                                        Font.beVietnamPro(14, weight: .medium)
                                    )
                                    .foregroundColor(Constants.ContentB)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 11)
                                    .glassEffectCompat()
                            }

                            if service.isCreatingExpense {
                                ProgressView()
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 11.5)
                            } else {
                                ToolbarIconButton(systemName: "checkmark") {
                                    guard pendingExpenseAmount > 0,
                                        !pendingExpenseMemberIds.isEmpty,
                                        let tripId
                                    else { return }
                                    Task {
                                        let home = service.homeCurrency
                                        let picked = pendingExpenseCurrency
                                        let hasCurrencyChoice =
                                            service.displayCurrencies.count >= 2
                                        let isLocal =
                                            hasCurrencyChoice
                                            && picked != nil
                                            && picked != home
                                        let success =
                                            await service.createExpense(
                                                tripId: tripId,
                                                name: pendingExpenseName.isEmpty
                                                    ? "Expense"
                                                    : pendingExpenseName,
                                                amount: pendingExpenseAmount,
                                                category:
                                                    pendingExpenseCategory,
                                                memberIds:
                                                    pendingExpenseMemberIds,
                                                originalAmount: isLocal
                                                    ? pendingExpenseAmount
                                                    : nil,
                                                originalCurrency: isLocal
                                                    ? picked
                                                    : nil
                                            )
                                        if success {
                                            UIApplication.shared.sendAction(
                                                #selector(
                                                    UIResponder
                                                        .resignFirstResponder
                                                ),
                                                to: nil,
                                                from: nil,
                                                for: nil
                                            )
                                            isAddingExpense = false
                                            pendingExpenseName = ""
                                            pendingExpenseAmount = 0
                                            pendingExpenseCurrency = nil
                                            pendingExpenseCategory = "FOOD"
                                            pendingExpenseMemberIds = []
                                            expenseFormResetToken += 1
                                        }
                                    }
                                }
                                .disabled(
                                    pendingExpenseAmount <= 0
                                        || pendingExpenseMemberIds.isEmpty
                                        || service.isCreatingExpense
                                )
                            }
                        }
                    }
                } else if !isOffline {
                    GlassContainerCompat() {
                        HStack(spacing: -4) {
                            ToolbarIconButton(
                                systemName: "person.badge.plus",
                                horizontalPadding: 13,
                                verticalPadding: 11.5
                            ) {
                                isShowingInvite = true
                            }

                            Menu {
                                if isCreator {
                                    Button {
                                        guard service.canEditHomeCurrency else {
                                            isShowingCurrencyLockedAlert = true
                                            return
                                        }
                                        pendingGroupCurrency = service.homeCurrency
                                        isPresentingGroupCurrencySheet = true
                                    } label: {
                                        Label(
                                            "Group currency · \(service.homeCurrency?.symbol ?? "—")",
                                            systemImage: "dollarsign.circle"
                                        )
                                        .foregroundStyle(
                                            service.canEditHomeCurrency ? .primary : .secondary
                                        )
                                    }

                                    Button {
                                        guard service.canEditHomeCurrency else {
                                            isShowingCurrencyLockedAlert = true
                                            return
                                        }
                                        pendingLocalCurrency = service.primaryLocalCurrency
                                        isPresentingLocalCurrencySheet = true
                                    } label: {
                                        Label(
                                            "Local currency · \(service.primaryLocalCurrency?.symbol ?? "Add")",
                                            systemImage: "airplane"
                                        )
                                        .foregroundStyle(
                                            service.canEditHomeCurrency ? .primary : .secondary
                                        )
                                    }

                                    if isOngoingTrip {
                                        Button {
                                            isShowingTripDatesSheet = true
                                        } label: {
                                            Label(
                                                tripDatesMenuLabel,
                                                systemImage: "calendar"
                                            )
                                        }
                                    }

                                    // Below iOS 26 the system renders menu
                                    // dividers as thick gray section bands that
                                    // read as ugly; iOS 26's refined separators
                                    // look right. Only show them on iOS 26+ and
                                    // let the uniform per-item separators carry
                                    // the menu below.
                                    if #available(iOS 26.0, *) {
                                        Divider()
                                    }

                                    let showsPrimaryTripAction =
                                        isPlanningTrip || isOngoingTrip

                                    if isPlanningTrip {
                                        Button {
                                            guard !service.isStartingTrip else {
                                                return
                                            }
                                            pendingStartDate = service.tripStartDate ?? Date()
                                            pendingEndDate = service.tripEndDate
                                            isShowingStartTripSheet = true
                                        } label: {
                                            Label(
                                                service.isStartingTrip
                                                    ? String(localized: "Starting...")
                                                    : String(localized: "Start Trip Now"),
                                                systemImage: "play.fill"
                                            )
                                        }
                                        .disabled(service.isStartingTrip)
                                    }

                                    if isOngoingTrip {
                                        Button {
                                            guard !service.isEndingTrip else { return }
                                            isShowingEndTripConfirm = true
                                        } label: {
                                            Label(
                                                "End trip",
                                                systemImage: "hand.wave"
                                            )
                                        }
                                    }

                                    if showsPrimaryTripAction {
                                        // iOS 26+ only — see note above.
                                        if #available(iOS 26.0, *) {
                                            Divider()
                                        }
                                    }

                                    Button(role: .destructive) {
                                        guard !service.isDeletingTrip else {
                                            return
                                        }
                                        isShowingDeleteTripConfirm = true
                                    } label: {
                                        Label(
                                            "Delete trip",
                                            systemImage: "trash"
                                        )
                                    }
                                } else {
                                    Button {
                                        guard let tripId else { return }
                                        Task {
                                            await service.fetchLeavePreview(tripId: tripId)
                                            isShowingLeaveSheet = true
                                        }
                                    } label: {
                                        Label(
                                            "Leave group",
                                            systemImage:
                                                "rectangle.portrait.and.arrow.right"
                                        )
                                    }
                                }
                            } label: {
                                ToolbarIconButton(
                                    systemName: "ellipsis",
                                    horizontalPadding: 12,
                                    verticalPadding: 18
                                )
                            }
                        }
                    }
                }
            }
            .sharedBackgroundHiddenCompat()
        }
    }

    /// Lifecycle: initial load, connectivity, notifications, role dialog.
    private func applyLifecycle(to content: some View) -> some View {
        content
        .task {
            guard let tripId else { return }
            realtimeService.joinTripRoom(tripId: tripId)
            hasVault = await TripVaultService.shared.hasVault(tripId: tripId)
            async let tripDetailTask: () = service.loadTripDetail(tripId: tripId)
            async let friendsTask: () = friendService.loadFriends()
            async let planItemsTask: () = service.fetchAllTripPlanItems(tripId: tripId)
            async let breakdownTask: () = service.fetchBreakdown(tripId: tripId)
            _ = await (tripDetailTask, friendsTask, planItemsTask, breakdownTask)
            if service.expenses.isEmpty {
                await service.fetchExpenses(tripId: tripId)
            }
            if hasVault {
                await refreshEndConsensusState(tripId: tripId)
                await refreshVaultLeaveRequests(tripId: tripId)
            }
            applyInitialHistoryRouteIfNeeded()
            // Arrived from ProcessPinView's "Add to Trips": jump to Your Plan
            // and force-refresh so the just-created plan items are visible.
            // (The one-shot replaces a .marketplacePlanApplied post that would
            // be lost — this view mounts after that notification fires.)
            if DeepLinkRouter.shared.consumePlanRefresh(tripId: tripId) {
                selectedTab = .yourPlan
                await service.fetchAllTripPlanItems(
                    tripId: tripId,
                    force: true
                )
            }
        }
        .onChange(of: networkMonitor.isOnline) { wasOnline, isOnline in
            // Came back online (cached data OR an uncached offline error): pull
            // fresh data and re-enable editing. (A Notification would not re-run
            // .task.) Gate on the false→true transition, not isServingCachedData,
            // so the deep-link-to-uncached-trip case reloads too.
            guard !wasOnline, isOnline, let tripId else { return }
            Task {
                await service.loadTripDetail(tripId: tripId, force: true)
                await service.fetchExpenses(tripId: tripId, force: true)
                await service.fetchAllTripPlanItems(tripId: tripId, force: true)
                await service.fetchBreakdown(tripId: tripId, force: true)
            }
        }
        .onDisappear {
            guard let tripId else { return }
            realtimeService.leaveTripRoom(tripId: tripId)
        }
        .captureStableDismiss(stableDismiss)
        .onChange(of: selectedTab) { _, newTab in
            guard let tripId else { return }
            switch newTab {
            case .history:
                if service.expenses.isEmpty {
                    Task { await service.fetchExpenses(tripId: tripId) }
                }
            case .yourPlan:
                if service.allPlanItems.isEmpty {
                    Task { await service.fetchAllTripPlanItems(tripId: tripId) }
                }
            case .note:
                if noteService.notes.isEmpty {
                    Task { await noteService.fetchNotes(tripId: tripId) }
                }
            // case .photo:
            //     if service.photos.isEmpty {
            //         Task { await service.fetchPhotos(tripId: tripId) }
            //     }
            case .insight:
                Task {
                    if service.expenses.isEmpty {
                        await service.fetchExpenses(tripId: tripId)
                    }
                    if service.breakdown == nil {
                        await service.fetchBreakdown(tripId: tripId)
                    }
                }
            default:
                break
            }
        }
        // A vault payment writes an expense, so the history below has to be
        // reloaded or the payment appears only after leaving and coming back.
        .onReceive(NotificationCenter.default.publisher(for: .vaultBalanceChanged)) { _ in
            guard let tripId else { return }
            Task {
                // First deposit creates the vault; flip history/settlement to
                // the vault path without waiting for a full screen remount.
                hasVault = await TripVaultService.shared.hasVault(tripId: tripId)
                await service.loadTripDetail(tripId: tripId, force: true)
                await service.fetchExpenses(tripId: tripId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripMemberRoleUpdated)) { notification in
            guard
                let tripId,
                let updatedTripId = notification.userInfo?["tripId"] as? Int,
                updatedTripId == tripId
            else { return }
            Task { await service.loadTripDetail(tripId: tripId, force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .marketplacePlanApplied)) { _ in
            guard let tripId else { return }
            selectedTab = .yourPlan
            Task { await service.fetchAllTripPlanItems(tripId: tripId, force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripPhotoUploaded)) { notification in
            guard
                let currentTripId = tripId,
                let uploadedTripId = notification.userInfo?["tripId"] as? Int,
                uploadedTripId == currentTripId
            else {
                return
            }

            Task {
                await service.fetchPhotos(tripId: currentTripId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripRealtimeEnded)) { notification in
            guard
                let currentTripId = tripId,
                let endedTripId = notification.userInfo?["tripId"] as? Int,
                endedTripId == currentTripId
            else {
                return
            }

            Task {
                await handleRealtimeTripEnded(tripId: currentTripId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripEndRequestUpdated)) { notification in
            guard
                let currentTripId = tripId,
                let updatedTripId = notification.userInfo?["tripId"] as? Int,
                updatedTripId == currentTripId
            else { return }

            let status = notification.userInfo?["status"] as? String ?? ""
            Task {
                await handleEndConsensusRealtime(
                    tripId: currentTripId,
                    status: status
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripRealtimeDeleted)) { notification in
            guard
                let currentTripId = tripId,
                let deletedTripId = notification.userInfo?["tripId"] as? Int,
                deletedTripId == currentTripId,
                !isCreator
            else {
                return
            }

            isAddingBudget = false
            isAddingExpense = false
            isShowingTripDeletedAlert = true
        }
    }

    @MainActor
    private func handleTripMemberRemovedNotification(_ notification: Notification) {
        guard
            let currentTripId = tripId,
            let removedTripId = notification.userInfo?["tripId"] as? Int,
            removedTripId == currentTripId
        else { return }

        let removedUserId = notification.userInfo?["userId"] as? Int
        let myId = userProfileService.profile?.id

        Task { @MainActor in
            if let removedUserId, let myId, removedUserId == myId {
                hostLeaveRequest = nil
                isShowingLeaveSheet = false
                NotificationCenter.default.post(name: .tripLeft, object: nil)
                stableDismiss()
                return
            }

            if let removedUserId {
                dismissedHostLeaveUserIds.remove(removedUserId)
                vaultLeaveRequestsByUserId.removeValue(forKey: removedUserId)
                if hostLeaveRequest?.userId == removedUserId {
                    hostLeaveRequest = nil
                }
                service.removeMemberLocally(userId: removedUserId)
            }
            await refreshVaultLeaveRequests(
                tripId: currentTripId,
                presentSheet: false
            )
            await service.loadTripDetail(tripId: currentTripId, force: true)
            await service.fetchExpenses(tripId: currentTripId, force: true)
        }
    }

    @ViewBuilder
    private var tabContentView: some View {
        Group {
            switch selectedTab {
            case .history:
                historyTab
            case .yourPlan:
                planTab
            case .note:
                noteTab
            // case .photo:
            //     photoTab
            case .insight:
                insightTab
            case .members:
                membersTab
            }
        }
        .id(selectedTab)
        .transition(.opacity.combined(with: .blurReplace))
        .animation(.snappy(duration: 0.25), value: selectedTab)
    }

    @ViewBuilder
    private var historyTab: some View {
        // A vault trip has one history, not two. The vault's own list is the
        // superset: it carries the deposits, which never become expenses, and
        // every payment leaves an expense behind anyway.
        if hasVault {
            VaultHistoryView(
                tripId: tripId ?? 0,
                members: service.trip?.members ?? trip?.members ?? []
            ) { payload in
                NotificationCenter.default.post(
                    name: .vaultSendAgain,
                    object: payload
                )
            }
        } else {
            TripHistorySection(
                groupedHistory: service.groupedHistory,
                isLoading: service.isLoadingExpenses,
                onBudgetTapped: { budgetId in
                    selectedBudgetId = budgetId
                },
                onExpenseTapped: { expenseId in
                    // Expense detail (ExpenseDto) isn't cached — disable offline.
                    guard !isOffline else { return }
                    selectedExpenseId = expenseId
                }
            )
        }
    }

    @ViewBuilder
    private var planTab: some View {
        TripPlanSection(
            tripId: tripId,
            allPlanItems: service.allPlanItems,
            availableDayNumbers: service.availablePlanningDays(),
            isLoading: service.isLoadingPlanItems,
            isPlanningMode: isPlanningTrip,
            dateForDay: { service.planDate(forDay: $0) },
            dateStringForDay: { service.planDateString(forDay: $0) },
            onAddPlanTapped: { dateString in
                createPlanDate = dateString
                createPlanDayNumber = nil
                createPlanFormToken += 1
                isShowingCreatePlan = true
            },
            onPlanTapped: { planItem in
                selectedPlanRoute = SelectedPlanRoute(
                    id: Int(planItem.id),
                    planItem: planItem
                )
            },
            onAddPlanTappedDay: { dayNumber in
                createPlanDayNumber = dayNumber
                createPlanDate = ""
                createPlanFormToken += 1
                isShowingCreatePlan = true
            },
            onShowRearrangeSheet: { _ in
                rearrangeMode = isOngoingTrip ? .dates : .days
                isShowingRearrangeSheet = true
            },
            canAddDay: service.availablePlanningDays().count < 14,
            onAddDayTapped: { service.addPlanningDay() },
            onViewDayMapTapped: { dayLabel, pins, routeLegs in
                selectedDayMap = SelectedDayMap(
                    id: pins.first?.id ?? 0,
                    dayLabel: dayLabel,
                    pins: pins,
                    routeLegs: routeLegs
                )
            },
            isReadOnly: isOffline
        )
    }

    private var tripDatesMenuLabel: String {
        let start = service.tripStartDate
        let end = service.tripEndDate
        switch (start, end) {
        case let (start?, end?):
            return String(localized: "Trip dates · \(DisplayFormatters.monthDay(start)) – \(DisplayFormatters.monthDay(end))", comment: "Trip date range; %1$@ = start date, %2$@ = end date")
        case let (start?, nil):
            return String(localized: "Trip dates · \(DisplayFormatters.monthDay(start)) – ?", comment: "Trip date range with unknown end; %@ = start date")
        default:
            return String(localized: "Trip dates · Set", comment: "Menu label prompting the user to set trip dates")
        }
    }

    @MainActor
    private func handleTripDatesConfirmed(start: Date, end: Date) {
        guard let tripId else { return }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let newCount = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        let lostCount = service.planItemCount(beyondDay: newCount)
        if lostCount > 0 {
            pendingScheduleConfirmStart = start
            pendingScheduleConfirmEnd = end
            scheduleShrinkLostCount = lostCount
            isShowingScheduleShrinkConfirm = true
            return
        }
        Task {
            _ = await service.updateTripSchedule(
                tripId: tripId,
                startDate: start,
                endDate: end
            )
        }
    }

    private var rearrangeSheetItems: [RearrangeDateItem] {
        let days = service.availablePlanningDays()
        switch rearrangeMode {
        case .days:
            return days.map { day in
                RearrangeDateItem(
                    id: "\(day)",
                    title: "Day \(day)",
                    dayNumber: day,
                    date: service.planDate(forDay: day),
                    subtitle: subtitleForDay(day)
                )
            }
        case .dates:
            return days.map { day in
                let dateValue = service.planDateString(forDay: day) ?? "\(day)"
                return RearrangeDateItem(
                    id: dateValue,
                    title: dateSheetTitle(for: dateValue),
                    dayNumber: day,
                    date: service.planDate(forDay: day),
                    subtitle: subtitleForDay(day)
                )
            }
        }
    }

    private func subtitleForDay(_ day: Int) -> String? {
        let items: [PlanItemDto]
        if isOngoingTrip, let dateString = service.planDateString(forDay: day) {
            items = service.allPlanItems.filter { $0.planDate == dateString }
        } else {
            items = service.allPlanItems.filter { Int($0.dayNumber ?? 0) == day }
        }
        let titles = items
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.title }
        guard !titles.isEmpty else { return nil }
        let preview = titles.prefix(3).joined(separator: ", ")
        return titles.count > 3 ? "\(preview)…" : preview
    }

    private var currentAvailableDates: [(label: String, value: String)] {
        return service.availablePlanningDays().compactMap { day in
            guard
                let date = service.planDate(forDay: day),
                let value = service.planDateString(forDay: day)  // wire value, unchanged
            else { return nil }
            // label is DISPLAY (day-of-month); value stays the wire string.
            return (label: date.formatted(.dateTime.day()), value: value)
        }
    }

    private func handleRearrange(_ items: [RearrangeDateItem]) {
        switch rearrangeMode {
        case .days:
            let orderedDays = items.compactMap { Int($0.id) }
            let currentDays = service.availablePlanningDays()
            guard orderedDays.count == currentDays.count,
                  orderedDays != currentDays else { return }
            service.rearrangePlanningDays(orderedDays)
        case .dates:
            let orderedDateValues = items.map(\.id)
            let slotDateValues = currentAvailableDates.map { $0.value }
            guard orderedDateValues.count == slotDateValues.count,
                  orderedDateValues != slotDateValues else { return }
            service.rearrangePlanDates(
                orderedDateValues: orderedDateValues,
                slotDateValues: slotDateValues
            )
        }
    }

    private func handleDeleteRearrangeItem(_ item: RearrangeDateItem) {
        switch rearrangeMode {
        case .days:
            guard let day = Int(item.id) else { return }
            service.deletePlanningDay(day)
        case .dates:
            guard let tripId else { return }
            service.deletePlanItems(onDate: item.id, tripId: tripId)
        }
    }

    private func dateSheetTitle(for value: String) -> String {
        // Parse the wire string with a fixed POSIX formatter…
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        // …then render for DISPLAY in the current locale.
        return DisplayFormatters.monthDay(date)
    }
    
    @ViewBuilder
    private var noteTab: some View {
        if let tripId {
            TripTodoSection(service: noteService, tripId: tripId)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var insightTab: some View {
        TripInsightSection(
            service: service,
            currentUserId: userProfileService.profile?.id
        )
    }
    
    @ViewBuilder
    private var photoTab: some View {
        TripPhotoSection(
            photos: service.photos,
            isLoading: service.isLoadingPhotos,
            hasMore: service.hasMorePhotos,
            isUploading: service.isUploadingPhotos,
            uploadProgress: service.uploadProgress,
            onLoadMore: {
                guard let tripId else { return }
                Task { await service.fetchMorePhotos(tripId: tripId) }
            },
            onPhotoTapped: {
                isShowingGallery = true
            },
            onPhotosSelected: { items in
                guard let tripId else { return }
                Task {
                    var images: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(
                            type: Data.self
                        ),
                            let uiImage = UIImage(data: data)
                        {
                            images.append(uiImage)
                        }
                    }
                    await service.uploadPhotos(
                        tripId: tripId,
                        images: images
                    )
                }
            }
        )
    }

    /// Ordinary members get no badge: a row saying "Member" beside every name
    /// is noise, and the point of the badge is to pick out the two who are not.
    private static func roleBadge(
        for role: Components.Schemas.TripMemberRole
    ) -> String? {
        switch role {
        case .HOST: return String(localized: "Host")
        case .CO_HOST: return String(localized: "Co-host")
        case .MEMBER: return nil
        }
    }

    @ViewBuilder
    private var membersTab: some View {
        let currentUserId = userProfileService.profile?.id
        let friendUserIds = Set(friendService.friends.map { $0.user.id })
        let mutualFriendsByUserId = Dictionary(
            uniqueKeysWithValues: friendService.friends.map {
                ($0.user.id, $0.mutualFriendCount)
            }
        )
        let proStatusByUserId = Dictionary(
            uniqueKeysWithValues: friendService.friends.map {
                ($0.user.id, $0.user.isPro)
            }
        )
        let currentUserIsPro = userProfileService.profile?.isPro ?? false

        let members = service.trip?.members ?? trip?.members ?? []

        let entries = members.map { member in
                let isSelf = member.userId == currentUserId
                let isFriend = isSelf || friendUserIds.contains(member.userId)
                let mutualFriendCount =
                    mutualFriendsByUserId[member.userId] ?? 0
                let isPro = isSelf
                    ? currentUserIsPro
                    : (proStatusByUserId[member.userId] ?? false)

                let role = member.role.value1
                return MemberListEntry(
                    id: "\(member.id)",
                    name: member.displayName,
                    subtitleText: String(localized: "\(mutualFriendCount) mutual friends", comment: "%lld = number of mutual friends"),
                    avatarUrl: member.avatarUrl,
                    actionText: isFriend ? String(localized: "Friend", comment: "Member is already a friend") : String(localized: "Add", comment: "Add member as friend"),
                    actionStyle: isFriend ? .disabled : .dark,
                    showsAction: !isSelf,
                    showsRemoveAction: isCreator && !isSelf,
                    roleText: Self.roleBadge(for: role),
                    showsRoleAction: isCreator && !isSelf,
                    roleActionTitle: role == .CO_HOST
                        ? String(localized: "Remove as co-host")
                        : String(localized: "Make co-host"),
                    clearVaultLeaveTitle: {
                        guard isCreator, !isSelf, hasVault else { return nil }
                        if vaultLeaveRequestsByUserId[member.userId] != nil {
                            return String(localized: "Confirm leave")
                        }
                        return String(localized: "Mark paid for leave")
                    }(),
                    isPro: isPro
                )
            }
        let membersByEntryId = Dictionary(
            uniqueKeysWithValues: members.map { ("\($0.id)", $0) }
        )
        MemberList(
            entries: entries,
            onActionTapped: { entry in
                guard let member = membersByEntryId[entry.id] else { return }
                guard let friendCode = member.friendCode, !friendCode.isEmpty else {
                    return
                }
                pendingFriendCode = friendCode
            },
            onRoleTapped: { entry in
                guard let member = membersByEntryId[entry.id], let tripId else { return }
                let isCoHost = member.role.value1 == .CO_HOST
                Task {
                    _ = await service.setMemberRole(
                        tripId: tripId,
                        userId: member.userId,
                        role: isCoHost ? .MEMBER : .CO_HOST
                    )
                }
            },
            onClearVaultLeaveTapped: { entry in
                guard let member = membersByEntryId[entry.id], let tripId else { return }
                if let request = vaultLeaveRequestsByUserId[member.userId] {
                    dismissedHostLeaveUserIds.remove(member.userId)
                    hostLeaveRequest = request
                    return
                }
                Task {
                    _ = await service.clearVaultLeave(
                        tripId: tripId,
                        userId: member.userId
                    )
                }
            },
            onRowTapped: { entry in
                guard let member = membersByEntryId[entry.id] else { return }
                guard member.userId != currentUserId else { return }  // tapping self → no-op
                selectedMemberUserId = member.userId
            }
        )
    }
}

extension TripDetailView {
    @MainActor
    private func selectTripTab(_ tab: TripTab) {
        guard tab != selectedTab else { return }

        if tab == .insight && !storeManager.isPro {
            isShowingInsightPaywall = true
            return
        }

        selectedTab = tab
        if tab != .insight {
            lastNonInsightTab = tab
        }
    }

    @MainActor
    private func handleInsightPaywallClosed() {
        isShowingInsightPaywall = false
        handleInsightPaywallDismissed()
    }

    @MainActor
    private func handleInsightPaywallDismissed() {
        if storeManager.isPro {
            selectedTab = .insight
        } else if selectedTab == .insight {
            selectedTab = lastNonInsightTab
        }
    }

    @MainActor
    private func refreshTripDetail() async {
        guard let tripId else { return }

        // Start ALL tasks upfront to avoid cancellation gaps between await phases
        async let tripTask: () = service.loadTripDetail(tripId: tripId, force: true)
        async let friendsTask: () = friendService.loadFriends()
        async let expensesTask: () = service.fetchExpenses(tripId: tripId, force: true)
        async let photosTask: () = service.fetchPhotos(tripId: tripId)
        async let planItemsTask: () = service.fetchAllTripPlanItems(tripId: tripId, force: true)

        // Await all at once - no gap for cancellation
        _ = await (tripTask, friendsTask, expensesTask, photosTask, planItemsTask)
    }

    @MainActor
    private func applyInitialHistoryRouteIfNeeded() {
        guard !hasHandledInitialHistoryRoute else { return }

        if let initialBudgetId {
            selectedTab = .history
            selectedBudgetId = initialBudgetId
            hasHandledInitialHistoryRoute = true
            return
        }

        if let initialExpenseId {
            selectedTab = .history
            selectedExpenseId = initialExpenseId
            hasHandledInitialHistoryRoute = true
            return
        }

        if let initialPlanItemId,
           let planItem = service.allPlanItems.first(where: { Int($0.id) == initialPlanItemId }) {
            selectedTab = .yourPlan
            selectedPlanRoute = SelectedPlanRoute(
                id: Int(planItem.id),
                planItem: planItem
            )
            hasHandledInitialHistoryRoute = true
            return
        }
    }

    @MainActor
    private func siblingPlanItems(for item: PlanItemDto) -> [PlanItemDto] {
        let all = service.allPlanItems
        if let dayNumber = item.dayNumber {
            return all.filter { $0.dayNumber == dayNumber }
        }
        if let planDate = item.planDate {
            return all.filter { $0.planDate == planDate }
        }
        return all.filter { $0.id == item.id }
    }

    @MainActor
    private func startTripIfPossible(
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async {
        guard let tripId else { return }

        let result = await service.startTrip(
            tripId: tripId,
            startDate: startDate,
            endDate: endDate
        )
        switch result {
        case .success:
            isAddingBudget = false
            isAddingExpense = false
            isShowingStartTripSheet = false
            NotificationCenter.default.post(
                name: .tripStatusChanged,
                object: nil
            )
        case .blockedByMemberConflicts(let memberNames):
            let names = memberNames.joined(separator: ", ")
            if memberNames.count == 1 {
                startTripAlertMessage =
                    String(localized: "\(names) is currently on another trip. They need to end or leave that trip before you can start this one.", comment: "%@ = a member's name; shown when one member is on another trip")
            } else {
                startTripAlertMessage =
                    String(localized: "\(names) are currently on other trips. They need to end or leave their trips before you can start this one.", comment: "%@ = comma-separated member names; shown when multiple members are on other trips")
            }
            isShowingStartTripSheet = false
            isShowingStartTripAlert = true
        case .failure(let message):
            startTripAlertMessage = message
            isShowingStartTripSheet = false
            isShowingStartTripAlert = true
        }
    }

    @MainActor
    private func handleRealtimeTripEnded(tripId: Int) async {
        guard !isShowingEndTrip else { return }

        isAddingBudget = false
        isAddingExpense = false
        isShowingEndReview = false
        isShowingEndWaiting = false
        isEndApprovalPending = false
        await presentEndedTrip(tripId: tripId)
    }

    @MainActor
    private func presentEndedTrip(tripId: Int) async {
        if service.photos.isEmpty {
            await service.fetchPhotos(tripId: tripId)
        }
        await service.loadTripDetail(tripId: tripId, force: true)
        NotificationCenter.default.post(
            name: .tripStatusChanged,
            object: nil
        )
        isShowingEndTrip = true
    }

    @MainActor
    private func refreshVaultLeaveRequests(
        tripId: Int,
        presentSheet: Bool = true
    ) async {
        let isCreator =
            service.trip?.createdById == userProfileService.profile?.id
            || trip?.createdById == userProfileService.profile?.id
        guard isCreator, hasVault else {
            vaultLeaveRequestsByUserId = [:]
            return
        }
        let items = await service.listVaultLeaveRequests(tripId: tripId)
        vaultLeaveRequestsByUserId = Dictionary(
            uniqueKeysWithValues: items.map { ($0.userId, $0) }
        )
        let pendingIds = Set(items.map(\.userId))
        dismissedHostLeaveUserIds = dismissedHostLeaveUserIds.intersection(pendingIds)
        if presentSheet {
            presentHostLeaveSheetIfNeeded()
        }
    }

    /// Leave-settle deposit landed → announce host and show waiting sheet.
    @MainActor
    private func autoAnnounceAfterLeaveDeposit(tripId: Int) async {
        isAnnouncingLeave = true
        let ok = await service.announceVaultLeave(tripId: tripId)
        isAnnouncingLeave = false
        await service.fetchLeavePreview(tripId: tripId)
        let pending = service.leavePreview?.leaveRequestPending == true
        if ok || pending {
            // Contribute sheet must finish tearing down first.
            try? await Task.sleep(for: .milliseconds(350))
            isShowingLeaveSheet = true
        } else {
            leaveAnnounceError =
                service.error
                ?? String(localized: "Failed to announce leave")
        }
    }

    @MainActor
    private func showMemberLeftToast(_ displayName: String) {
        memberLeftToast = String(localized: "\(displayName) left")
        Task {
            try? await Task.sleep(for: .seconds(3))
            if memberLeftToast != nil {
                memberLeftToast = nil
            }
        }
    }

    /// Oldest pending leave request the host has not dismissed this session.
    @MainActor
    private func presentHostLeaveSheetIfNeeded() {
        guard hostLeaveRequest == nil, !isShowingLeaveSheet else { return }
        let next = vaultLeaveRequestsByUserId.values
            .filter { !dismissedHostLeaveUserIds.contains($0.userId) }
            .sorted { $0.requestedAt < $1.requestedAt }
            .first
        hostLeaveRequest = next
    }

    @MainActor
    private func refreshEndConsensusState(tripId: Int) async {
        guard let request = await service.fetchVaultEndRequest(tripId: tripId)
        else {
            isEndApprovalPending = false
            endConsensusRequest = nil
            return
        }
        endConsensusRequest = request
        isEndApprovalPending = request.status.value1 == .PENDING
    }

    /// Vault card "Waiting for approval" — Review if not voted, else Waiting.
    @MainActor
    private func openEndConsensusFromCard() {
        guard let tripId else { return }
        Task {
            await refreshEndConsensusState(tripId: tripId)
            guard let request = endConsensusRequest,
                  request.status.value1 == .PENDING
            else { return }
            if request.myDecision == nil {
                isShowingEndReview = true
            } else {
                isShowingEndWaiting = true
            }
        }
    }

    @MainActor
    private func handleEndConsensusRealtime(tripId: Int, status: String) async {
        await refreshEndConsensusState(tripId: tripId)

        switch status {
        case "PENDING":
            isEndApprovalPending = true
            // Surface Review immediately for members who have not voted yet.
            if endConsensusRequest?.myDecision == nil,
               !isShowingEndReview,
               !isShowingEndWaiting,
               !isShowingEndDenied,
               !isShowingEndTrip
            {
                isShowingEndReview = true
            }
        case "DENIED":
            isEndApprovalPending = false
            if endConsensusRequest != nil {
                isShowingEndReview = false
                isShowingEndWaiting = false
                isShowingEndDenied = true
            }
        case "APPROVED":
            isEndApprovalPending = false
            isShowingEndReview = false
            isShowingEndWaiting = false
            // tripEnded realtime also fires; avoid double-present if already ending.
            if !isShowingEndTrip {
                await presentEndedTrip(tripId: tripId)
            }
        default:
            break
        }
    }
}

extension Notification.Name {
    static let tripLeft = Notification.Name("tripLeft")
    static let tripStatusChanged = Notification.Name("tripStatusChanged")
    static let tripCreated = Notification.Name("tripCreated")
    static let tripEnded = Notification.Name("tripEnded")
    static let tripPhotoUploaded = Notification.Name("tripPhotoUploaded")
    static let tripRealtimeEnded = Notification.Name("tripRealtimeEnded")
    static let tripRealtimeDeleted = Notification.Name("tripRealtimeDeleted")
    static let tripSettlementUpdated = Notification.Name("tripSettlementUpdated")
    static let tripMemberRoleUpdated = Notification.Name("tripMemberRoleUpdated")
    static let switchToMarketTab = Notification.Name("switchToMarketTab")
    static let listingUpdated = Notification.Name("listingUpdated")
    static let marketplacePlanApplied = Notification.Name("marketplacePlanApplied")
    static let marketplacePlanAcquired = Notification.Name("marketplacePlanAcquired")
    static let marketplaceListingRated = Notification.Name("marketplaceListingRated")
    static let friendRemoved = Notification.Name("friendRemoved")
    static let tripScheduleUpdated = Notification.Name("tripScheduleUpdated")
    // Posted by ProcessPinView after pins are attached to a trip, so MainView
    // can switch to the Trip tab and push that trip's detail.
    static let openTripDetail = Notification.Name("openTripDetail")
    /// Welcome "Add money" (and similar): open Profile → wallet detail; optional deposit sheet.
    static let openOnePlanWallet = Notification.Name("openOnePlanWallet")
}

#Preview {
    NavigationStack {
        TripDetailView()
    }
    .environment(UserProfileService())
    .environment(RealtimeService())
}
