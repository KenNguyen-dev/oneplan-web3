//
//  GroupView.swift
//  OnePlan
//
//  Created by ken on 26/2/26.
//

import SwiftUI

private struct TripOngoingRoute: Identifiable, Hashable {
    let id = UUID()
    let tripId: Int
    let initialAddExpense: Bool
}

private struct TripPlanItemRoute: Identifiable, Hashable {
    let id = UUID()
    let tripId: Int
    let planItemId: Int
}

struct TripView: View {
    @Environment(StoreManager.self) private var storeManager
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Binding var deepLinkTripId: Int?
    @Binding var deepLinkPlanItem: PlanItemDeepLink?
    let service: TripService
    let tripDetailService: TripDetailService
    @State private var navigationPath = NavigationPath()
    // Guards against `onChange(…, initial: true)` firing twice for a single
    // deepLinkTripId set (the tab-mount transition re-evaluates `initial`
    // before our nil reset propagates), which otherwise double-pushes the trip.
    @State private var lastDeepLinkedTripId: Int?
    @State private var navigateToCreateTrip = false
    @State private var selectedOngoingRoute: TripOngoingRoute?
    @State private var selectedPlanItemRoute: TripPlanItemRoute?
    @State private var showingTripLimitPaywall = false

    init(
        deepLinkTripId: Binding<Int?> = .constant(nil),
        deepLinkPlanItem: Binding<PlanItemDeepLink?> = .constant(nil),
        tripService: TripService,
        tripDetailService: TripDetailService
    ) {
        self._deepLinkTripId = deepLinkTripId
        self._deepLinkPlanItem = deepLinkPlanItem
        self.service = tripService
        self.tripDetailService = tripDetailService
    }

    private let planningColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    private var canCreatePlanningTrip: Bool {
        service.canCreatePlanningTrip(isPro: storeManager.isPro)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            AppScreenContainer {
                if service.isLoadingTrips {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.ongoingTrips.isEmpty
                    && service.planningTrips.isEmpty
                {
                    VStack {
                        Spacer(minLength: 0)
                        if networkMonitor.isOnline {
                            EmptyHome(onStartNewTripTapped: handleCreateTripTapped)
                        } else {
                            EmptyOffline()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if service.isServingCachedData {
                                OfflineBanner(cachedAt: nil)
                            }
                            // Ongoing Trip section
                            if let ongoing = service.ongoingTrips.first {
                                Text("Ongoing Trip")
                                    .font(
                                        Font.beVietnamPro(16, weight: .medium)
                                    )
                                    .foregroundColor(Constants.ContentM)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .topLeading
                                    )

                                OngoingCard(
                                    tripName: ongoing.name,
                                    coverImageUrl: ongoing.coverImageUrl,
                                    locationLabel: formatLocation(
                                        ongoing.location?.value1
                                    ),
                                    memberAvatarUrls: ongoingTripMemberAvatarUrls(
                                        for: Int(ongoing.id)
                                    ),
                                    onCardTapped: {
                                        selectedOngoingRoute = TripOngoingRoute(
                                            tripId: Int(ongoing.id),
                                            initialAddExpense: false
                                        )
                                    },
                                    onNewExpenseTapped: {
                                        selectedOngoingRoute = TripOngoingRoute(
                                            tripId: Int(ongoing.id),
                                            initialAddExpense: true
                                        )
                                    }
                                )
                            }

                            // Planning section
                            if !service.planningTrips.isEmpty {
                                Text("Planning")
                                    .font(
                                        Font.beVietnamPro(16, weight: .medium)
                                    )
                                    .foregroundColor(Constants.ContentM)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .topLeading
                                    )

                                LazyVGrid(columns: planningColumns, spacing: 22)
                                {
                                    ForEach(
                                        Array(
                                            service.planningTrips.enumerated()
                                        ),
                                        id: \.element.id
                                    ) { index, trip in
                                        NavigationLink(value: trip.id) {
                                            PlanningDestinationCard(
                                                trip: trip,
                                                rotation: index.isMultiple(
                                                    of: 2
                                                )
                                                    ? .degrees(-1.2)
                                                    : .degrees(1.2)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, 16)
                }
            }
            .navigationDestination(for: Int.self) { tripId in
                TripDetailView(tripId: tripId)
            }
            .navigationDestination(item: $selectedOngoingRoute) { route in
                TripDetailView(
                    tripId: route.tripId,
                    initialAddExpense: route.initialAddExpense
                )
            }
            .navigationDestination(item: $selectedPlanItemRoute) { route in
                TripDetailView(
                    tripId: route.tripId,
                    initialPlanItemId: route.planItemId
                )
            }
            .navigationDestination(isPresented: $navigateToCreateTrip) {
                CreateTripView()
            }
            .task {
                await loadTripData()
            }
            .onReceive(NotificationCenter.default.publisher(for: .tripLeft)) { _ in
                Task { await reloadTripData() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tripStatusChanged)) { _ in
                Task { await reloadTripData() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tripCreated)) { _ in
                Task { await reloadTripData() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tripEnded)) { _ in
                navigationPath = NavigationPath()
                Task { await reloadTripData() }
            }
            .onChange(of: networkMonitor.isOnline) { wasOnline, isOnline in
                // Came back online (e.g. from the cached card or EmptyOffline) →
                // reload the real trip lists.
                guard !wasOnline, isOnline else { return }
                Task { await reloadTripData() }
            }
            .onChange(of: deepLinkTripId, initial: true) { _, tripId in
                guard let tripId else {
                    // Reset so the same trip can be deep-linked again later.
                    lastDeepLinkedTripId = nil
                    return
                }
                // Skip the duplicate fire that carries the same id before the
                // nil reset lands — only the first push should happen.
                guard tripId != lastDeepLinkedTripId else { return }
                lastDeepLinkedTripId = tripId
                navigationPath.append(tripId)
                deepLinkTripId = nil
            }
            .onChange(of: deepLinkPlanItem, initial: true) { _, plan in
                if let plan {
                    selectedPlanItemRoute = TripPlanItemRoute(
                        tripId: plan.tripId,
                        planItemId: plan.planItemId
                    )
                    deepLinkPlanItem = nil
                }
            }
            .sheet(isPresented: $showingTripLimitPaywall) {
                SubscriptionView()
            }
        }
    }

    private func handleCreateTripTapped() {
        if canCreatePlanningTrip {
            navigateToCreateTrip = true
        } else {
            showingTripLimitPaywall = true
        }
    }

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

    @MainActor
    private func loadTripData() async {
        await service.listMyTrips()

        guard let ongoingTripId = service.ongoingTrips.first.map({ Int($0.id) })
        else {
            return
        }

        await tripDetailService.loadTripDetail(tripId: ongoingTripId)
        await tripDetailService.fetchExpenses(tripId: ongoingTripId)
    }

    @MainActor
    private func reloadTripData() async {
        await service.listMyTrips(force: true)

        guard let ongoingTripId = service.ongoingTrips.first.map({ Int($0.id) })
        else {
            return
        }

        await tripDetailService.loadTripDetail(tripId: ongoingTripId)
        await tripDetailService.fetchExpenses(
            tripId: ongoingTripId,
            force: true
        )
    }
}

#Preview {
    TripView(tripService: TripService(), tripDetailService: TripDetailService())
        .environment(UserProfileService())
        .background(Constants.Background.ignoresSafeArea())
}
