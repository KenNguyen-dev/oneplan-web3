import SwiftUI

/// Screen 3: this member approved; waiting on the rest of the group.
/// Figma `4575:1957` Pending approval.
struct TripEndWaitingView: View {
    let tripId: Int
    var request: TripEndRequestDto
    var onBack: () -> Void = {}
    var onAllApproved: () -> Void = {}
    var onDenied: (_ request: TripEndRequestDto) -> Void = { _ in }

    @State private var liveRequest: TripEndRequestDto

    init(
        tripId: Int,
        request: TripEndRequestDto,
        onBack: @escaping () -> Void = {},
        onAllApproved: @escaping () -> Void = {},
        onDenied: @escaping (_ request: TripEndRequestDto) -> Void = { _ in }
    ) {
        self.tripId = tripId
        self.request = request
        self.onBack = onBack
        self.onAllApproved = onAllApproved
        self.onDenied = onDenied
        _liveRequest = State(initialValue: request)
    }

    var body: some View {
        VStack(spacing: 0) {
            TripEndConsensusChrome.BackHeader(onBack: onBack)

            Spacer(minLength: 0)

            VStack(spacing: 19) {
                TripEndConsensusChrome.waitingGlyph

                VStack(spacing: 3) {
                    Text("Waiting for others to approve.")
                        .font(Font.beVietnamPro(20))
                        .tracking(-0.8)
                        .foregroundStyle(Constants.Neutral950)
                        .multilineTextAlignment(.center)

                    Text(
                        "You have confirmed. Please wait for other members to confirm their transactions."
                    )
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.ContentM)
                    .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            TripEndConsensusChrome.GoBackButton(action: onBack)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .top) {
            TripEndConsensusChrome.statusGradient(kind: .waiting)
                .frame(height: 392)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
        }
        .background(Constants.Background)
        .onReceive(
            NotificationCenter.default.publisher(for: .tripEndRequestUpdated)
        ) { note in
            guard (note.userInfo?["tripId"] as? Int) == tripId else { return }
            Task { await refresh() }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        do {
            guard let latest = try await TripEndConsensusService.shared.getRequest(
                tripId: tripId
            ) else { return }
            liveRequest = latest
            if latest.status.value1 == .APPROVED {
                onAllApproved()
            } else if latest.status.value1 == .DENIED {
                onDenied(latest)
            }
        } catch {
            // Keep the last known status; realtime may catch up.
        }
    }
}
