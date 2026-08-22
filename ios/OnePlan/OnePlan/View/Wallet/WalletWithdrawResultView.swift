import SwiftUI
import UIKit

/// What became of a withdrawal.
struct WalletWithdrawResult {
    enum Status {
        case completed
        /// On the chain, but its confirmation has not come back. Never shown as
        /// failed: the money has already left.
        case processing
        case failed
    }

    let status: Status
    let amountMicro: UInt64
    let recipient: String
    let signature: String
    let date: Date
}

/// Receipt for a withdrawal (Figma 4239:14190 / 14799 / 14888).
///
/// Every fee line says covered rather than a number: the member paid nothing
/// and holds no SOL to pay with.
struct WalletWithdrawResultView: View {
    let result: WalletWithdrawResult
    var onDone: () -> Void
    var onSendAgain: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 0) {
                    amountBlock
                        .padding(.top, 48)
                        .padding(.bottom, 28)

                    detailsShell
                        .padding(.horizontal, 7)
                }
                .padding(.bottom, 24)
            }

            Button(action: onDone) {
                Text("Go back")
                    .font(Font.beVietnamPro(17))
                    .tracking(-0.68)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Constants.Neutral900, in: Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .top) {
            statusGradient
                .frame(height: 345)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
        }
        .background(Constants.Background)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("Move money")
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
                .foregroundStyle(Constants.ContentB)

            HStack {
                Button(action: onDone) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Constants.Neutral900)
                        .frame(width: 32, height: 32)
                }
                .vaultHeaderChip()
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Amount

    private var amountBlock: some View {
        VStack(spacing: 20) {
            Text("Amount")
                .font(Font.beVietnamPro(18))
                .tracking(-0.36)
                .foregroundStyle(Color(red: 0.533, green: 0.533, blue: 0.533))

            Text(amountText)
                .font(Font.beVietnamPro(48))
                .tracking(-2.4)
                .foregroundStyle(Constants.Neutral950)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // Figma Processing has no secondary CTA; Completed shows Send again.
            if result.status == .completed {
                Button(action: onSendAgain) {
                    Text("Send again")
                        .font(Font.beVietnamPro(15))
                        .tracking(-0.75)
                        .foregroundStyle(Constants.ContentB)
                        .frame(width: 147, height: 44)
                }
                .glassEffectCompat(in: Capsule(), interactive: false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Details

    private var detailsShell: some View {
        VStack(spacing: 8) {
            VStack(spacing: 16) {
                row("Status") { statusLabel }
                row("Date") {
                    value(Self.dateFormatter.string(from: result.date))
                }
                row("Recipient") {
                    copyable(
                        display: Self.shorten(result.recipient),
                        full: result.recipient
                    )
                }
                row("Transaction ID") {
                    copyable(
                        display: Self.shorten(result.signature),
                        full: result.signature
                    )
                }
                row("Onchain fees") { covered }
                row("Estimated gas fee") { covered }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Constants.White, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            explorerLink
                .padding(.bottom, 4)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            Color(red: 0.937, green: 0.937, blue: 0.937),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private var explorerLink: some View {
        Link(destination: Self.explorerURL(result.signature)) {
            HStack(spacing: 5) {
                Text("Check on explorer")
                    .font(Font.beVietnamPro(16))
                    .tracking(-0.32)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .regular))
            }
            .foregroundStyle(Color(red: 0.224, green: 0.224, blue: 0.224))
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 5) {
            statusIcon
            Text(statusTitle)
                .font(Font.beVietnamPro(16))
                .tracking(-0.32)
                .foregroundStyle(Color(red: 0.224, green: 0.224, blue: 0.224))
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch result.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Constants.Green400)
                .frame(width: 19, height: 19)
        case .processing:
            processingCubes
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Constants.Secondary)
                .frame(width: 19, height: 19)
        }
    }

    /// Orange cube cluster matching Figma processing glyph.
    private var processingCubes: some View {
        let orange = Color(red: 1, green: 0.55, blue: 0.25)
        return ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(orange)
                .frame(width: 7, height: 7)
                .offset(x: -3, y: 3)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(orange.opacity(0.85))
                .frame(width: 7, height: 7)
                .offset(x: 3, y: 3)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(orange)
                .frame(width: 7, height: 7)
                .offset(y: -3)
        }
        .frame(width: 19, height: 19)
        .accessibilityHidden(true)
    }

    private var statusTitle: LocalizedStringKey {
        switch result.status {
        case .completed: "Completed"
        case .processing: "Processing"
        case .failed: "Failed"
        }
    }

    private var statusGradient: some View {
        let stops: [Gradient.Stop]
        switch result.status {
        case .completed:
            stops = [
                .init(color: Color(red: 0.706, green: 0.875, blue: 1), location: 0),
                .init(color: Color(red: 0.984, green: 0.925, blue: 0.843), location: 0.514),
                .init(color: Constants.Background, location: 1),
            ]
        case .processing:
            stops = [
                .init(color: Color(red: 1, green: 0.784, blue: 0.706), location: 0),
                .init(color: Color(red: 0.984, green: 0.925, blue: 0.843), location: 0.514),
                .init(color: Constants.Background, location: 1),
            ]
        case .failed:
            stops = [
                .init(color: Color(red: 1, green: 0.706, blue: 0.714), location: 0),
                .init(color: Color(red: 0.984, green: 0.843, blue: 0.843), location: 0.514),
                .init(color: Constants.Background, location: 1),
            ]
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private var covered: some View {
        Text("Covered")
            .font(Font.beVietnamPro(16))
            .tracking(-0.32)
            .foregroundStyle(Constants.Green400)
    }

    private var amountText: String {
        let value = Double(result.amountMicro) / 1_000_000
        if value == value.rounded() {
            return String(format: "$%.0f", value)
        }
        return String(format: "$%.2f", value)
    }

    private func row<V: View>(
        _ label: LocalizedStringKey,
        @ViewBuilder value: () -> V
    ) -> some View {
        HStack {
            Text(label)
                .font(Font.beVietnamPro(15))
                .tracking(-0.45)
                .foregroundStyle(Constants.ContentM)
            Spacer(minLength: 8)
            value()
        }
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(Font.beVietnamPro(16))
            .tracking(-0.32)
            .foregroundStyle(Color(red: 0.224, green: 0.224, blue: 0.224))
    }

    private func copyable(display: String, full: String) -> some View {
        Button {
            UIPasteboard.general.string = full
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(spacing: 5) {
                value(display)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(Constants.ContentM)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(display)")
    }

    private static func shorten(_ text: String) -> String {
        guard text.count > 12 else { return text }
        return "\(text.prefix(5))...\(text.suffix(4))"
    }

    private static func explorerURL(_ signature: String) -> URL {
        URL(string: "https://explorer.solana.com/tx/\(signature)?cluster=devnet")!
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter
    }()
}

#Preview("Completed") {
    WalletWithdrawResultView(
        result: .init(
            status: .completed,
            amountMicro: 20_000_000,
            recipient: "0xd3abcdadg7xyz",
            signature: "h42fjh24abcd",
            date: Date()
        ),
        onDone: {}
    )
}

#Preview("Processing") {
    WalletWithdrawResultView(
        result: .init(
            status: .processing,
            amountMicro: 20_000_000,
            recipient: "0xd3abcdadg7xyz",
            signature: "h42fjh24abcd",
            date: Date()
        ),
        onDone: {}
    )
}

#Preview("Failed") {
    WalletWithdrawResultView(
        result: .init(
            status: .failed,
            amountMicro: 20_000_000,
            recipient: "0xd3abcdadg7xyz",
            signature: "h42fjh24abcd",
            date: Date()
        ),
        onDone: {}
    )
}
