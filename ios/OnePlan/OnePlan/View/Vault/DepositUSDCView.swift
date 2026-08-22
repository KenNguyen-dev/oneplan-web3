import SwiftUI

/// Shows the trip vault address as a QR code and as text, so a member can send
/// USDC in from any wallet or exchange.
///
/// There is no amount field on purpose: the deposit comes from outside the app,
/// so the app cannot constrain it. `TripVaultService.loadBalance` picks it up.
///
/// The chain warning is the most important text on the screen. USDC exists on
/// many chains and sending from the wrong one loses the funds, which no amount
/// of app-side handling can undo.
struct DepositUSDCView: View {
    let address: String
    var onDone: () -> Void = {}

    @State private var hasCopied = false

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3))
                .frame(width: 35, height: 5)

            VStack(spacing: 1) {
                Text("Deposit USDC")
                    .font(Font.beVietnamPro(20))
                    .tracking(-0.8)
                    .foregroundStyle(Constants.ContentB)

                chainWarning
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.ContentM)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                StyledQRCodeView(
                    content: address,
                    color: Constants.Black,
                    size: 283,
                    moduleRoundness: 0.5
                )

                addressText
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding(38)
            .frame(maxWidth: .infinity)
            .background(Constants.Surface)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6.3, y: 4)

            Spacer(minLength: 0)

            Button(action: copyAddress) {
                Text(hasCopied ? "Copied" : "Copy address")
                    .font(Font.beVietnamPro(15))
                    .tracking(-0.75)
                    .foregroundStyle(Constants.ContentB)
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            // Figma's button resolves to a solid Surface fill under its glass
            // layers, so a capsule plus its two shadows is what it actually
            // draws. glassEffectCompat rendered grey against the white sheet.
            .background(Constants.Surface, in: Capsule())
            .shadow(color: .black.opacity(0.10), radius: 1)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .accessibilityLabel("Copy the group wallet address")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Surface)
    }

    /// "Solana" is emphasised because it is the part that must not be misread.
    private var chainWarning: Text {
        Text("Make sure to deposit USDC via ")
            + Text("Solana")
                .font(Font.beVietnamProItalic(14, weight: .bold))
                .foregroundColor(Constants.Black)
            + Text(" chain only.")
    }

    /// Highlights the leading and trailing characters, which is how people
    /// actually check an address: nobody reads the middle.
    private var addressText: Text {
        let highlight = 6
        guard address.count > highlight * 2 else {
            return Text(address)
                .font(Font.beVietnamPro(14))
                .foregroundColor(Constants.BlueBase)
        }
        let head = String(address.prefix(highlight))
        let tail = String(address.suffix(highlight))
        let middle = String(
            address.dropFirst(highlight).dropLast(highlight)
        )
        let font = Font.beVietnamPro(14)
        return Text(head).font(font).foregroundColor(Constants.BlueBase)
            + Text(middle).font(font).foregroundColor(Constants.ContentB)
            + Text(tail).font(font).foregroundColor(Constants.BlueBase)
    }

    private func copyAddress() {
        UIPasteboard.general.string = address
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { hasCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { hasCopied = false }
        }
    }
}

#Preview {
    DepositUSDCView(address: "8pjmDZvmRzjcSwzffqnsdzsPRb3nV9BiVDhGU3vmR7uD")
        .background(Constants.Background)
}
