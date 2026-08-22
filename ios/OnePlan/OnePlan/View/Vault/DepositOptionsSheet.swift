import SwiftUI

/// How money gets into the group wallet (Figma 4234:13896).
///
/// Only OnePlan Wallet works today. Fiat is shown so the sheet matches the
/// product map, but it does not open a flow yet.
struct DepositOptionsSheet: View {
    var onOnchain: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3))
                .frame(width: 35.194, height: 4.888)
                .padding(.top, 12)

            VStack(spacing: 32) {
                header

                VStack(spacing: 20) {
                    // Fiat first in the design. No handler yet — same as the old
                    // "Global account / Coming soon" row, kept visible on purpose.
                    optionRow(
                        icon: "depositOptionFiat",
                        title: "Fiat",
                        subtitle: "Receive assets via global bank account",
                        action: nil
                    )
                    optionRow(
                        icon: "depositOptionWallet",
                        title: "OnePlan Wallet",
                        subtitle: "Receive assets via OnePlan Wallet",
                        action: onOnchain
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.White)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image("depositContributeArrow")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Contribute")
                    .font(Font.beVietnamPro(20))
                    .tracking(-0.8)
                    .foregroundStyle(Constants.Neutral950)

                Text("Choose one of the options below\nto deposit crypto")
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.ContentM)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// `action` is nil for an option that does not exist yet: it still reads as
    /// a row so the list shows where the feature will be, but nothing about it
    /// invites a tap.
    private func optionRow(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 8) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Font.beVietnamPro(16))
                        .tracking(-0.48)
                        .foregroundStyle(Constants.Neutral950)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(Font.beVietnamPro(14))
                        .tracking(-0.42)
                        .foregroundStyle(Constants.Neutral950.opacity(0.4))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Constants.Neutral950.opacity(0.35))
                    .frame(width: 18, height: 18)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityHint(action == nil ? "Coming soon" : "")
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            DepositOptionsSheet {}
                .presentationDetents([.height(340)])
                .presentationCornerRadius(44)
        }
}
