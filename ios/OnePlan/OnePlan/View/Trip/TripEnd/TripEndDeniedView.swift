import SwiftUI

/// Screen 4: someone denied ending; trip stays ONGOING.
/// Figma `4575:15260` Someone deny.
struct TripEndDeniedView: View {
    let request: TripEndRequestDto
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            TripEndConsensusChrome.BackHeader(onBack: onDismiss)

            Spacer(minLength: 0)

            VStack(spacing: 19) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Constants.Secondary)
                    .frame(width: 19, height: 19)

                VStack(spacing: 3) {
                    Text("Someone denied")
                        .font(Font.beVietnamPro(20))
                        .tracking(-0.8)
                        .foregroundStyle(Constants.Neutral950)
                        .multilineTextAlignment(.center)

                    Text(
                        "There has been a rejection. Please check the transactions and then perform the \"End Trip\" action again."
                    )
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.ContentM)
                    .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)

            memberList
                .padding(.top, 28)
                .padding(.horizontal, 7)

            Spacer(minLength: 0)

            TripEndConsensusChrome.GoBackButton(action: onDismiss)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .top) {
            TripEndConsensusChrome.statusGradient(kind: .denied)
                .frame(height: 392)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
        }
        .background(Constants.Background)
    }

    private var memberList: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ForEach(request.members, id: \.userId) { member in
                    memberRow(member)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Constants.White)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(8)
        .background(
            Color(red: 0.937, green: 0.937, blue: 0.937),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private func memberRow(
        _ member: Components.Schemas.TripEndVoteMemberDto
    ) -> some View {
        HStack {
            Text(member.displayName)
                .font(Font.beVietnamPro(15))
                .tracking(-0.45)
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)

            Spacer(minLength: 8)

            statusTrailing(member.decision?.value1)
        }
    }

    @ViewBuilder
    private func statusTrailing(_ decision: TripEndVoteDecision?) -> some View {
        switch decision {
        case .APPROVED:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Constants.Green400)
                    .frame(width: 19, height: 19)
                Text("Approved")
                    .font(Font.beVietnamPro(16))
                    .tracking(-0.32)
                    .foregroundStyle(Color(red: 0.224, green: 0.224, blue: 0.224))
            }
        case .DENIED:
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Constants.Secondary)
                    .frame(width: 19, height: 19)
                Text("Denied")
                    .font(Font.beVietnamPro(16))
                    .tracking(-0.32)
                    .foregroundStyle(Color(red: 0.224, green: 0.224, blue: 0.224))
            }
        case .none:
            Text("Waiting")
                .font(Font.beVietnamPro(16))
                .tracking(-0.32)
                .foregroundStyle(Constants.ContentM)
        }
    }
}
