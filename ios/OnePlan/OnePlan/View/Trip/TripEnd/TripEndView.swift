//
//  EndTripView.swift
//  OnePlan
//
//  Created by ken on 4/3/26.
//

import SwiftUI
import UIKit

private enum TripEndTab: String, Hashable {
    case history
    case breakdown

    var symbolImage: String {
        switch self {
        case .history:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .breakdown:
            return "chart.bar.xaxis"
        }
    }

    var title: String {
        switch self {
        case .history:
            return String(localized: "History", comment: "Trip-end tab: history")
        case .breakdown:
            return String(localized: "Settlement", comment: "Trip-end tab: settlement breakdown")
        }
    }
}

struct TripEndView: View {
    enum EntryMode {
        case tripEndFlow
        case endedList
        case leavingMember(settlement: LeaveSettlementDto)
    }

    let service: TripDetailService
    let tripId: Int
    let entryMode: EntryMode
    @Environment(\.dismiss) private var dismiss
    @Environment(UserProfileService.self) private var userProfileService
    @Environment(RealtimeService.self) private var realtimeService
    @State private var activeTab: TripEndTab = .history
    @State private var showMainView = false
    @State private var isShowingDeleteTripConfirm = false
    @State private var deleteTripErrorMessage = ""
    @State private var isShowingDeleteTripError = false
    /// A trip whose money is held in a group wallet winds up through the wallet,
    /// not through the app's own tally of who owes whom.
    @State private var hasVault = false
    @State private var vaultBalanceMicro: UInt64?

    /// Indicative VND for the Trip Balance chip (same ballpark as the vault card).
    private static let indicativeUsdcToVnd: Double = 26_500

    private var tripBalanceChipText: String? {
        guard hasVault, let micro = vaultBalanceMicro else { return nil }
        let vnd = Double(micro) / 1_000_000 * Self.indicativeUsdcToVnd
        let formatted = CurrencyFormatter.formatWhole(vnd)
        return String(localized: "Trip Balance +\(formatted)")
    }

    private func refreshVaultBalanceChip() async {
        try? await TripVaultService.shared.loadBalance(tripId: tripId)
        vaultBalanceMicro = TripVaultService.shared.balanceMicro
    }

    init(
        service: TripDetailService,
        tripId: Int,
        entryMode: EntryMode = .tripEndFlow
    ) {
//        Self.configureNativeTabBarAppearance()
        self.service = service
        self.tripId = tripId
        self.entryMode = entryMode
    }

    private var isLeavingMemberMode: Bool {
        if case .leavingMember = entryMode { return true }
        return false
    }

    private var leaveSettlement: LeaveSettlementDto? {
        if case .leavingMember(let settlement) = entryMode {
            return settlement
        }
        return nil
    }

    private var isOwner: Bool {
        guard let userId = userProfileService.profile?.id,
            let createdById = service.trip?.createdById
        else {
            return false
        }
        return userId == createdById
    }

    var body: some View {
        TabView(selection: $activeTab) {
            Group {
                // Web3 keeps vault rows for History, but reuses the trip-end
                // hero / album / plan / map shell from Figma 4013:12858.
                TripEndHistory(
                    service: service,
                    tripId: tripId,
                    usesVaultHistory: hasVault,
                    onVaultSendAgain: { payload in
                        NotificationCenter.default.post(
                            name: .vaultSendAgain,
                            object: payload
                        )
                    }
                )
            }
                .background(self.backgroundGradient)
                .tabItem {
                    Label(
                        TripEndTab.history.title,
                        systemImage: TripEndTab.history.symbolImage
                    )
                }
                .tag(TripEndTab.history)

            Group {
                if hasVault, !isLeavingMemberMode {
                    // Winding up a wallet trip is the settlement: it distributes
                    // what is left on chain and leaves the remainder as debts
                    // between members. A member leaving early is a different
                    // question, and keeps the app's own breakdown.
                    VaultSettlementView(
                        tripId: tripId,
                        coverImageUrl: service.trip?.coverImageUrl,
                        totalSpent: service.breakdown?.totalSpent
                            ?? service.totalSpent,
                        currency: Currency(from: service.trip?.currency.value1)
                            ?? .VND,
                        members: service.trip?.members ?? []
                    )
                } else {
                    TripEndBreakdown(
                        service: service,
                        tripId: tripId,
                        currentUserId: Int(userProfileService.profile?.id ?? 0),
                        currentUserAvatarUrl: userProfileService.profile?
                            .avatarUrl,
                        leaveSettlement: leaveSettlement,
                        onMarkAsDone: {
                            showMainView = true
                        }
                    )
                }
            }
            .background(self.backgroundGradient)
            .tabItem {
                Label(
                    TripEndTab.breakdown.title,
                    systemImage: TripEndTab.breakdown.symbolImage
                )
            }
            .tag(TripEndTab.breakdown)
        }
        .tint(Constants.BlueBase)
        .toolbarBackground(Constants.Background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .task {
            hasVault = await TripVaultService.shared.hasVault(tripId: tripId)
            if hasVault {
                await refreshVaultBalanceChip()
            }
        }
        // Settlement finishes async after Approve; WS alone does not update the
        // shared balance cache — refetch or the Trip Balance chip stays stale.
        .onReceive(NotificationCenter.default.publisher(for: .vaultBalanceChanged)) { note in
            guard hasVault else { return }
            if let id = note.userInfo?["tripId"] as? Int, id != tripId { return }
            Task { await refreshVaultBalanceChip() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultSettlementUpdated)) { note in
            guard hasVault else { return }
            if let id = note.userInfo?["tripId"] as? Int, id != tripId { return }
            Task { await refreshVaultBalanceChip() }
        }
        .task(id: tripId) {
            realtimeService.joinTripRoom(tripId: tripId)

            let isDifferentTrip = service.trip?.id != tripId

            await service.loadTripDetail(
                tripId: tripId,
                force: isDifferentTrip
            )

            // Skip expense fetch for leaving members - they have settlement data
            if !isLeavingMemberMode
                && (isDifferentTrip || service.expenses.isEmpty)
            {
                await service.fetchExpenses(
                    tripId: tripId,
                    force: isDifferentTrip
                )
            }

            if isDifferentTrip || service.photos.isEmpty {
                await service.fetchPhotos(tripId: tripId)
            }

            if isDifferentTrip || service.allPlanItems.isEmpty {
                await service.fetchAllTripPlanItems(tripId: tripId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripSettlementUpdated)) { notification in
            guard
                let updatedTripId = notification.userInfo?["tripId"] as? Int,
                updatedTripId == tripId,
                leaveSettlement == nil
            else { return }

            Task {
                await service.fetchBreakdown(tripId: tripId, force: true)
            }
        }
        .onChange(of: activeTab) { _, newTab in
            guard newTab == .breakdown, leaveSettlement == nil else { return }
            realtimeService.joinTripRoom(tripId: tripId)
            Task { await service.fetchBreakdown(tripId: tripId, force: true) }
        }
        .fullScreenCover(isPresented: $showMainView) {
            MainView(deepLinkTripId: .constant(nil), initialTab: .home)
                .interactiveDismissDisabled(true)
        }
        .alert("Delete trip?", isPresented: $isShowingDeleteTripConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard !service.isDeletingTrip else { return }
                Task {
                    let success = await service.deleteTrip(tripId: tripId)
                    if success {
                        handleDeleteSuccess()
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    switch entryMode {
                    case .tripEndFlow:
                        NotificationCenter.default.post(
                            name: .tripEnded,
                            object: nil
                        )
                        showMainView = true
                    case .endedList:
                        dismiss()
                    case .leavingMember:
                        showMainView = true
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Constants.ContentB)
                }
                .contentShape(Circle())
                .disabled(service.isDeletingTrip)
                .opacity(service.isDeletingTrip ? 0.4 : 1)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if let tripBalanceChipText {
                    Text(tripBalanceChipText)
                        .font(Font.beVietnamPro(13))
                        .foregroundStyle(Constants.ContentB)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Color.white.opacity(0.55),
                            in: Capsule()
                        )
                }

                if service.isDeletingTrip {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Constants.BlueBase)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11.5)
                } else if isOwner {
                    ToolbarIconButton(
                        systemName: "trash",
                        foregroundColor: Constants.Warning500,
                        horizontalPadding: 13
                    ) {
                        isShowingDeleteTripConfirm = true
                    }
                }
            }
            .sharedBackgroundHiddenCompat()
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(
                    color: Color(red: 0.84, green: 0.89, blue: 1),
                    location: 0.00
                ),
                Gradient.Stop(
                    color: Constants.Background,
                    location: 0.27
                ),
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
        .ignoresSafeArea()
    }

//    private static func configureNativeTabBarAppearance() {
//        let appearance = UITabBarAppearance()
//        appearance.configureWithOpaqueBackground()
//        appearance.backgroundColor = UIColor(Constants.Background)
//        appearance.shadowColor = UIColor(Constants.Neutral200)
//
//        let itemAppearance = appearance.stackedLayoutAppearance
//        itemAppearance.selected.iconColor = UIColor(Constants.BlueBase)
//        itemAppearance.selected.titleTextAttributes = [
//            .foregroundColor: UIColor(Constants.BlueBase)
//        ]
//        itemAppearance.normal.iconColor = UIColor(Constants.ContentL)
//        itemAppearance.normal.titleTextAttributes = [
//            .foregroundColor: UIColor(Constants.ContentL)
//        ]
//
//        UITabBar.appearance().standardAppearance = appearance
//        UITabBar.appearance().scrollEdgeAppearance = appearance
//        UITabBar.appearance().tintColor = UIColor(Constants.BlueBase)
//        UITabBar.appearance().unselectedItemTintColor = UIColor(
//            Constants.ContentL
//        )
//    }

    private func handleDeleteSuccess() {
        NotificationCenter.default.post(name: .tripLeft, object: nil)

        switch entryMode {
        case .endedList:
            dismiss()
        case .tripEndFlow, .leavingMember:
            showMainView = true
        }
    }
}

#Preview {
    let service: TripDetailService = {
        let s = TripDetailService()

        let members: [TripMemberDto] = [
            .init(
                id: 1, userId: 1, displayName: "Ken",
                avatarUrl: nil, friendCode: "KEN01",
                inviteStatus: .init(value1: .ACCEPTED),
                role: .init(value1: .MEMBER),
                joinedAt: "2026-03-30",
                isPro: true
            ),
            .init(
                id: 2, userId: 2, displayName: "Minh",
                avatarUrl: nil, friendCode: "MINH02",
                inviteStatus: .init(value1: .ACCEPTED),
                role: .init(value1: .MEMBER),
                joinedAt: "2026-03-30",
                isPro: false
            ),
            .init(
                id: 3, userId: 3, displayName: "Linh",
                avatarUrl: nil, friendCode: "LINH03",
                inviteStatus: .init(value1: .ACCEPTED),
                role: .init(value1: .MEMBER),
                joinedAt: "2026-03-30",
                isPro: false
            ),
        ]

        s.trip = .init(
            id: 1,
            name: "Da Lat Trip",
            status: .init(value1: .ENDED),
            startDate: "2026-04-01",
            endDate: "2026-04-04",
            createdById: 1,
            createdAt: "2026-03-30",
            currency: .init(value1: .VND),
            localCurrencies: [],
            location: .init(
                value1: .init(
                    cityName: "Da Lat",
                    countryName: "Vietnam",
                    latitude: 11.9404,
                    longitude: 108.4583
                )
            ),
            members: members
        )

        s.expenses = [
            .init(
                id: 101,
                name: "Dinner at Memory Cafe",
                amount: 1_250_000,
                category: .init(value1: .FOOD),
                expenseDate: "2026-04-01T19:30:00.000Z",
                createdAt: "2026-04-01T19:30:00.000Z",
                paidBy: .init(
                    value1: .init(userId: 1, displayName: "Ken", avatarUrl: nil)
                ),
                sharedMembers: [
                    .init(userId: 1), .init(userId: 2), .init(userId: 3),
                ]
            ),
            .init(
                id: 102,
                name: "Cable car tickets",
                amount: 450_000,
                category: .init(value1: .TICKET),
                expenseDate: "2026-04-02T10:15:00.000Z",
                createdAt: "2026-04-02T10:15:00.000Z",
                paidBy: .init(
                    value1: .init(userId: 2, displayName: "Minh", avatarUrl: nil)
                ),
                sharedMembers: [.init(userId: 1), .init(userId: 2)]
            ),
            .init(
                id: 103,
                name: "Taxi to airport",
                amount: 320_000,
                category: .init(value1: .TRANSPORT),
                expenseDate: "2026-04-04T07:00:00.000Z",
                createdAt: "2026-04-04T07:00:00.000Z",
                paidBy: .init(
                    value1: .init(userId: 3, displayName: "Linh", avatarUrl: nil)
                ),
                sharedMembers: [
                    .init(userId: 1), .init(userId: 2), .init(userId: 3),
                ]
            ),
        ]

        s.budgets = [
            .init(
                id: 1,
                tripId: 1,
                name: "Group pool",
                amount: 3_000_000,
                perPersonAmount: 1_000_000,
                scope: .init(value1: .GROUP),
                createdAt: "2026-03-31T09:00:00.000Z",
                payments: [
                    .init(
                        id: 1, userId: 1, displayName: "Ken",
                        amount: 1_000_000, isPaid: true,
                        paidAt: "2026-03-31T09:00:00.000Z"
                    ),
                    .init(
                        id: 2, userId: 2, displayName: "Minh",
                        amount: 1_000_000, isPaid: true,
                        paidAt: "2026-03-31T10:00:00.000Z"
                    ),
                    .init(
                        id: 3, userId: 3, displayName: "Linh",
                        amount: 1_000_000, isPaid: false
                    ),
                ]
            )
        ]

        s.photos = [
            .init(
                id: 1, tripId: 1,
                url: "https://picsum.photos/seed/oneplan1/400/500",
                uploadedById: 1, uploaderDisplayName: "Ken",
                createdAt: "2026-04-01T11:00:00.000Z"
            ),
            .init(
                id: 2, tripId: 1,
                url: "https://picsum.photos/seed/oneplan2/400/500",
                uploadedById: 2, uploaderDisplayName: "Minh",
                createdAt: "2026-04-02T14:20:00.000Z"
            ),
            .init(
                id: 3, tripId: 1,
                url: "https://picsum.photos/seed/oneplan3/400/500",
                uploadedById: 3, uploaderDisplayName: "Linh",
                createdAt: "2026-04-03T18:05:00.000Z"
            ),
        ]

        s.breakdown = .init(
            totalSpent: 2_020_000,
            unsettledCount: 2,
            members: [
                .init(
                    userId: 1, displayName: "Ken", avatarUrl: nil,
                    totalDeposit: 1_000_000, totalPaid: 1_250_000,
                    totalShare: 700_000, netBalance: 550_000,
                    isAllSettled: false,
                    expenses: [
                        .init(
                            expenseId: 101, expenseName: "Dinner at Memory Cafe",
                            shareAmount: 416_667, isSettled: false, shareId: 1001
                        ),
                        .init(
                            expenseId: 103, expenseName: "Taxi to airport",
                            shareAmount: 106_667, isSettled: false, shareId: 1003
                        ),
                    ]
                ),
                .init(
                    userId: 2, displayName: "Minh", avatarUrl: nil,
                    totalDeposit: 1_000_000, totalPaid: 450_000,
                    totalShare: 750_000, netBalance: -300_000,
                    isAllSettled: false,
                    expenses: [
                        .init(
                            expenseId: 101, expenseName: "Dinner at Memory Cafe",
                            shareAmount: 416_667, isSettled: true, shareId: 1002
                        ),
                        .init(
                            expenseId: 102, expenseName: "Cable car tickets",
                            shareAmount: 225_000, isSettled: false, shareId: 1004
                        ),
                    ]
                ),
                .init(
                    userId: 3, displayName: "Linh", avatarUrl: nil,
                    totalDeposit: 0, totalPaid: 320_000,
                    totalShare: 523_333, netBalance: -203_333,
                    isAllSettled: true,
                    expenses: [
                        .init(
                            expenseId: 101, expenseName: "Dinner at Memory Cafe",
                            shareAmount: 416_667, isSettled: true, shareId: 1005
                        ),
                        .init(
                            expenseId: 103, expenseName: "Taxi to airport",
                            shareAmount: 106_667, isSettled: true, shareId: 1006
                        ),
                    ]
                ),
            ]
        )

        return s
    }()
    NavigationStack {
        TripEndView(service: service, tripId: 1)
    }
    .environment(UserProfileService())
    .environment(RealtimeService())
}
