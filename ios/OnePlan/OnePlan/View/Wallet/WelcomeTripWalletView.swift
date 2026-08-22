import SwiftUI

/// First-login trip wallet welcome — Figma `4251:16033` / `4251:15808`.
/// Presented as a bottom sheet, not a full-screen cover.
struct WelcomeTripWalletView: View {
    var onContinue: () -> Void
    /// Opens Profile → wallet detail → deposit sheet (see `.openOnePlanWallet`).
    var onAddMoney: () -> Void = {}
    var onClose: (() -> Void)?

    @State private var wallet = WalletService.shared
    @State private var address: String?
    @State private var setupError: String?
    @State private var showHowMoneyHeld = false

    private var isSettingUp: Bool { address == nil }
    private var dismissAction: () -> Void { onClose ?? onContinue }

    /// Figma link / Continue tint `#48B8FE` / `#48B9FF`.
    private static let accentSky = Color(red: 72 / 255, green: 185 / 255, blue: 255 / 255)
    private static let subtitleGray = Color(red: 0x99 / 255, green: 0x99 / 255, blue: 0x99 / 255)
    /// Figma close label / Add-money fill `#363636`.
    private static let ink = Color(red: 0x36 / 255, green: 0x36 / 255, blue: 0x36 / 255)

    var body: some View {
        VStack(spacing: 20) {
            toolbar

            header

            statusCard
                .padding(.horizontal, 20)

            fundingOptions
                .padding(.horizontal, 20)

            Spacer(minLength: 8)

            footer
                .padding(.horizontal, 16)
        }
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.White)
        .task { await setupWallet() }
        .sheet(isPresented: $showHowMoneyHeld) {
            HowMoneyIsHeldView(onClose: { showHowMoneyHeld = false })
                .presentationDetents([.large])
                .presentationCornerRadius(38)
                .presentationDragIndicator(.hidden)
        }
        .alert(
            "Could not set up wallet",
            isPresented: Binding(
                get: { setupError != nil },
                set: { if !$0 { setupError = nil } }
            ),
            actions: {
                Button("Retry") { Task { await setupWallet() } }
                Button("Continue anyway", role: .cancel, action: onContinue)
            },
            message: { Text(setupError ?? "") }
        )
    }

    /// Figma toolbar close: glass capsule, SF Symbol xmark 17 Medium, #727272.
    private var toolbar: some View {
        HStack {
            TripWalletSheetCloseButton(action: dismissAction)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Figma: Be Vietnam Pro Medium 28 / tracking -1.96 / #363636
            Text("Welcome to your trip wallet")
                .font(Font.beVietnamPro(28))
                .tracking(-1.96)
                .lineSpacing(28 * 0.2)
                .foregroundStyle(Self.ink)

            Text("One place to hold trip money and split it with friends")
                .font(Font.beVietnamPro(15))
                .tracking(-0.75)
                .foregroundStyle(Self.subtitleGray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var statusCard: some View {
        VStack(spacing: 8) {
            if let address {
                Image("tripWalletWelcomeWallet")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .frame(width: 40, height: 40)

                VStack(spacing: 8) {
                    Text(Self.shorten(address))
                        .font(Font.beVietnamPro(18))
                        .tracking(-0.54)
                        .foregroundStyle(Self.ink)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    // Figma `4251:16139`: black pill, white Regular 14, pad 12×6
                    Button(action: onAddMoney) {
                        Text("Add money to get start")
                            .font(Font.beVietnamPro(14))
                            .tracking(-0.28)
                            .foregroundStyle(Constants.White)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Self.ink, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Image("tripWalletWelcomeWallet")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .frame(width: 40, height: 40)

                VStack(spacing: 2) {
                    Text("Setting up your wallet")
                        .font(Font.beVietnamPro(18))
                        .tracking(-0.54)
                        .foregroundStyle(Self.ink)

                    Text("Few seconds")
                        .font(Font.beVietnamPro(14))
                        .tracking(-0.42)
                        .foregroundStyle(Self.ink.opacity(0.4))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(Constants.Neutral50, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var fundingOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            optionRow(
                asset: "tripWalletWelcomeGlobe",
                title: "Bank transfer",
                subtitle: "Add USD, EUR or VND from your bank"
            )
            optionRow(
                asset: "tripWalletWelcomeWalletSmall",
                title: "From a crypto wallet",
                subtitle: "Send USDC from any Solana wallet"
            )
            optionRow(
                asset: "tripWalletWelcomeFriends",
                title: "From a friend",
                subtitle: "Get money sent by another OnePlan user"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionRow(
        asset: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.beVietnamPro(18))
                    .tracking(-0.54)
                    .foregroundStyle(Constants.Neutral950)
                    .lineLimit(1)

                Text(subtitle)
                    .font(Font.beVietnamPro(15))
                    .tracking(-0.45)
                    .foregroundStyle(Constants.Neutral950.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Image("tripWalletWelcomeWalletSmall")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                disclosureText
            }

            Button(action: onContinue) {
                Text("Continue")
                    .font(Font.beVietnamPro(17))
                    .tracking(-0.68)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Self.accentSky,
                        in: Capsule(style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isSettingUp)
            .opacity(isSettingUp ? 0.5 : 1)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        }
    }

    private var disclosureText: some View {
        Text(disclosureAttributed)
            .font(Font.beVietnamPro(12))
            .tracking(-0.36)
            .tint(Self.accentSky)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    if url.scheme == "oneplan", url.host == "how-money-held" {
                        showHowMoneyHeld = true
                        return .handled
                    }
                    return .systemAction
                }
            )
    }

    private var disclosureAttributed: AttributedString {
        var body = AttributedString(
            String(localized: "Setting up a wallet creates a Solana account tied to your OnePlan sign-in, through our wallet provider. Payments need your approval, and spending from a trip fund above the trip's limit needs a second member to approve it too. OnePlan covers the network fees, so you never need to hold SOL. ")
        )
        body.foregroundColor = Self.subtitleGray

        var link = AttributedString(String(localized: "See how your money is held"))
        link.font = Font.beVietnamPro(12)
        link.foregroundColor = Self.accentSky
        link.link = URL(string: "oneplan://how-money-held")

        body.append(link)
        return body
    }

    private func setupWallet() async {
        setupError = nil
        do {
            address = try await wallet.ensureLinked()
        } catch {
            setupError = error.localizedDescription
        }
    }

    private static func shorten(_ address: String) -> String {
        guard address.count > 8 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }
}

#Preview("Setting up") {
    Color.gray.opacity(0.3)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            WelcomeTripWalletView(onContinue: {})
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
}
