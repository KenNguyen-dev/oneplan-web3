import SwiftUI

/// The Group Balance card shown at the top of a web3 trip.
///
/// Deliberately presentational: every value is passed in and every action is a
/// closure, so it previews without a network stack and `TripDetailView` stays the
/// only place that knows about services.
///
/// It is the vault counterpart to `HomeCard` and copies its chrome on purpose —
/// same 32pt radius, same dashed rim, same cover-image backdrop — so a trip does
/// not visibly change shape when it gains a vault.
struct TripVaultCard: View {
    let tripName: String
    let coverImageUrl: String?
    /// Vault balance converted to the trip's home currency.
    let balance: Double
    let currency: Currency
    /// Vault balance in USDC, the figure that is actually on chain.
    let balanceUsdc: Double
    /// While end-trip consensus is PENDING, replace Move token / Scan QR.
    var isWaitingForEndApproval: Bool = false
    /// True when the caller still needs to Approve/Deny (shows Review CTA).
    var needsEndTripReview: Bool = false
    var onDeposit: () -> Void = {}
    var onScanQR: () -> Void = {}
    var onWaitingForApproval: () -> Void = {}

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            nameHeader

            Spacer(minLength: 0)

            VStack(spacing: 5) {
                CurrencyDisplayField(
                    label: "Group Balance",
                    amount: balance,
                    currency: currency
                )
                Text(usdcText)
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.56)
                    .foregroundStyle(Constants.Neutral600)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Group {
                if isWaitingForEndApproval {
                    Button(action: onWaitingForApproval) {
                        // Figma `4600:1741` — label is always Waiting for approval;
                        // tap still routes to review vs waiting via `needsEndTripReview`.
                        Text("Waiting for approval")
                            .font(Font.beVietnamPro(15))
                            .tracking(-0.6)
                            .foregroundStyle(Constants.White)
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .glassEffectCompat(
                        in: Capsule(),
                        interactive: true,
                        tint: VaultPalette.accent
                    )
                } else {
                    HStack(alignment: .center, spacing: 6) {
                        // Vault-only chrome (Figma 4016:14636): same 15pt / 42pt as Scan QR.
                        // Do not reuse AddBudgetButton — that stays 14pt for Home "Add budget".
                        Button(action: onDeposit) {
                            Text("Move token")
                                .font(Font.beVietnamPro(15))
                                .tracking(-0.75)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Constants.ContentB)
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Constants.White)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .inset(by: 0.5)
                                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.07), radius: 12, y: 6)
                                .shadow(
                                    color: Color(red: 0.8, green: 0.86, blue: 0.94).opacity(0.35),
                                    radius: 18,
                                    y: 10
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: onScanQR) {
                            Text("Scan QR")
                                .font(Font.beVietnamPro(15))
                                .tracking(-0.6)
                                .foregroundStyle(Constants.White)
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        // Not glassProminentButtonStyleCompat: that tints with the
                        // brand blue, and this button is the lighter sky blue sampled
                        // from the design. Same glass treatment, different tint.
                        .glassEffectCompat(
                            in: Capsule(),
                            interactive: true,
                            tint: VaultPalette.accent
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .frame(height: 303)
        .background(alignment: .top) {
            Image("cardBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .cornerRadius(32)
        .overlay(
            RoundedRectangle(cornerRadius: 31, style: .continuous)
                .inset(by: 1.43)
                .stroke(
                    .white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                )
        )
        .shadow(color: Color(red: 0.35, green: 0.53, blue: 1).opacity(0.13), radius: 10.35)
        .shadow(color: Color(red: 0, green: 0.3, blue: 1).opacity(0.2), radius: 3.05, y: 2)
    }

    private var nameHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            tripAvatar
            Text(tripName)
                .font(Font.beVietnamPro(17))
                .tracking(-0.68)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Constants.ContentB)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(
            RoundedCorners(topLeft: 28, topRight: 28, bottomLeft: 6, bottomRight: 6)
        )
    }

    private var tripAvatar: some View {
        avatarImage
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.15), lineWidth: 0.489)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 15.642, y: 1.955)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let coverImageUrl, let url = URL(string: coverImageUrl) {
            CachedRemoteImage(url: url, targetSize: CGSize(width: 42, height: 42)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
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

    /// USDC is micro-precise on chain; show enough decimals that a 0.1% skim
    /// (e.g. 0.999) is not rounded into `"0.100"` by the fiat 2-place helpers.
    private var usdcText: String {
        CurrencyFormatter.formatUsdc(balanceUsdc) + " USDC"
    }
}

#Preview("With balance") {
    TripVaultCard(
        tripName: "Dubai 2025",
        coverImageUrl: nil,
        balance: 10_000_000,
        currency: .VND,
        balanceUsdc: 450
    )
    .padding(12)
    .background(Constants.Background)
}

#Preview("Empty vault") {
    TripVaultCard(
        tripName: "A trip with a very long name that has to truncate",
        coverImageUrl: nil,
        balance: 0,
        currency: .VND,
        balanceUsdc: 0
    )
    .padding(12)
    .background(Constants.Background)
}
