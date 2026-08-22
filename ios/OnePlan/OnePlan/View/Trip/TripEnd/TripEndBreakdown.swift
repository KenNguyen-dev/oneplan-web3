import SwiftUI

struct TripEndBreakdown: View {
    let service: TripDetailService
    let tripId: Int
    let currentUserId: Int
    let currentUserAvatarUrl: String?
    let leaveSettlement: LeaveSettlementDto?
    let onMarkAsDone: (() -> Void)?

    @State private var isShowingWalletQR = false

    init(
        service: TripDetailService,
        tripId: Int,
        currentUserId: Int,
        currentUserAvatarUrl: String? = nil,
        leaveSettlement: LeaveSettlementDto? = nil,
        onMarkAsDone: (() -> Void)? = nil
    ) {
        self.service = service
        self.tripId = tripId
        self.currentUserId = currentUserId
        self.currentUserAvatarUrl = currentUserAvatarUrl
        self.leaveSettlement = leaveSettlement
        self.onMarkAsDone = onMarkAsDone
    }

    private var otherMemberAvatarUrls: [String?] {
        service.trip?.members
            .filter { Int($0.userId) != currentUserId }
            .map { $0.avatarUrl } ?? []
    }

    private var tripCurrency: Currency {
        Currency(from: service.trip?.currency.value1) ?? .VND
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TripEndHeroHeader(
                    coverImageUrl: service.trip?.coverImageUrl,
                    totalSpent: service.breakdown?.totalSpent ?? service.totalSpent,
                    unsettledPaymentCount: leaveSettlement != nil
                        ? 1
                        : (service.breakdown?.unsettledCount ?? service.unsettledPaymentCount),
                    currency: tripCurrency
                )

                if let settlement = leaveSettlement {
                    TripEndLeaveSettlementItem(
                        settlement: settlement,
                        userAvatarUrl: currentUserAvatarUrl,
                        currency: tripCurrency,
                        onMarkAsDone: onMarkAsDone ?? {}
                    )
                    .padding(.horizontal, 12)
                } else if service.isLoadingBreakdown {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else if let breakdown = service.breakdown {
                    VStack(spacing: 8) {
                        ForEach(breakdown.members, id: \.userId) { member in
                            TripEndBreakdownItem(
                                member: member,
                                isCurrentUser: Int(member.userId) == currentUserId,
                                memberAvatarUrls: otherMemberAvatarUrls,
                                currency: tripCurrency,
                                onSettleAll: {
                                    _ = await service.settleAllShares(tripId: tripId)
                                },
                                onShowQR: { isShowingWalletQR = true }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.clear)
        .scrollIndicators(.hidden)
        .task {
            guard leaveSettlement == nil else { return }
            await service.fetchBreakdown(tripId: tripId)
        }
        .sheet(isPresented: $isShowingWalletQR) {
            DepositToOnePlanWalletView(
                mode: .receive,
                onBack: { isShowingWalletQR = false }
            )
            .presentationDetents([.fraction(0.8)])
            .presentationCornerRadius(48)
        }
    }
}

#Preview {
    TripEndBreakdown(service: TripDetailService(), tripId: 0, currentUserId: 0)
}
