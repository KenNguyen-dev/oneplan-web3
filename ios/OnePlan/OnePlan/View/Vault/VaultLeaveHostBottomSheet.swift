import SwiftUI

/// Host leave confirmation sheets
/// (Figma 4716:2227 / 4716:2108 / 4712:2514 / 4712:2689).
///
/// Amounts are **USDC** (vault ledger) — same as the member leave sheet.
/// Statuses: WAITING_DEPOSIT | READY | PAYOUT → then local `left` after confirm.
/// Confirm removes the member (+ payout when credit ≥ $0.01). No withdraw UI.
struct VaultLeaveHostBottomSheet: View {
    let request: Components.Schemas.VaultLeaveRequestDto
    var isWorking: Bool = false
    /// Called for READY / PAYOUT. Return `true` when the member was removed.
    var onConfirm: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .request

    /// Matches server `VAULT_LEAVE_DUST_MICRO` / member leave sheet.
    private static let displayDustMicro: Int64 = 10_000

    private enum Phase {
        case request
        case left
    }

    private var netMicro: Int64 {
        Int64(request.netMicro) ?? 0
    }

    private var announcedNetMicro: Int64 {
        Int64(request.announcedNetMicro) ?? netMicro
    }

    /// PAYOUT only for ≥ $0.01 (server + local dust floor).
    private var isPayout: Bool {
        guard phase == .request else { return false }
        guard request.status == "PAYOUT" else { return false }
        return displayAmountMicro >= UInt64(Self.displayDustMicro)
    }

    private var displayAmountMicro: UInt64 {
        switch phase {
        case .left:
            return 0
        case .request:
            switch request.status {
            case "WAITING_DEPOSIT":
                let owed = netMicro < 0 ? netMicro : announcedNetMicro
                return flooredAbs(owed)
            case "PAYOUT":
                let due = max(netMicro, announcedNetMicro)
                return flooredAbs(max(due, 0))
            case "READY":
                // Figma 4716:2108 — amount deposited to settle, not live net (~0).
                return UInt64(max(announcedNetMicro, 0))
            default:
                if abs(netMicro) >= Self.displayDustMicro {
                    return flooredAbs(netMicro)
                }
                return UInt64(max(announcedNetMicro, 0))
            }
        }
    }

    private func flooredAbs(_ signed: Int64) -> UInt64 {
        let absVal = abs(signed)
        guard absVal >= Self.displayDustMicro else { return 0 }
        return UInt64(absVal)
    }

    private var titleText: String {
        switch phase {
        case .left:
            return String(localized: "\(request.displayName) left")
        case .request:
            if isPayout {
                return String(localized: "Confirm action")
            }
            return String(localized: "\(request.displayName) is leaving")
        }
    }

    private var ctaTitle: String {
        if phase == .left { return String(localized: "Got it") }
        if isPayout { return String(localized: "Approve & send") }
        return String(localized: "Got it")
    }

    private var sheetHeight: CGFloat {
        isPayout ? 560 : 420
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3))
                .frame(width: 35.194, height: 4.888)
                .padding(.top, 12)

            VStack(spacing: 24) {
                Button { dismiss() } label: {
                    Image("vaultLeaveBackArrow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(90))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Back"))

                // Figma PAYOUT / READY — title + body + amount centered; full wrap.
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text(titleText)
                            .font(Font.beVietnamPro(16, weight: .medium))
                            .tracking(-0.48)
                            .foregroundStyle(Constants.Neutral950)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        bodyCopy
                            .tracking(-0.42)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(formatUsdc(displayAmountMicro))
                        .font(Font.beVietnamPro(32))
                        .tracking(-1.28)
                        .foregroundStyle(Constants.Neutral950)
                        .frame(maxWidth: .infinity)
                }

                if isPayout {
                    payoutAddressCard
                } else if phase == .request, let badge = statusBadge {
                    statusPill(badge)
                }
            }
            .padding(.bottom, 24)

            Spacer(minLength: 0)

            cta
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.White)
        .presentationDetents([.height(sheetHeight), .medium])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(44)
        .interactiveDismissDisabled(phase == .left && isWorking)
    }

    @ViewBuilder
    private var bodyCopy: some View {
        switch phase {
        case .left:
            highlightedNameCopy(
                prefix: "",
                name: request.displayName,
                suffix: " has left the group, and the final settlement has been completed."
            )
        case .request:
            if isPayout {
                highlightedNameCopy(
                    prefix: "",
                    name: request.displayName,
                    suffix: " is leaving the group and requesting a withdrawal of the remaining funds he has in the group pool."
                )
            } else {
                highlightedNameCopy(
                    prefix: "Please confirm receipt of the amount below, transferred by ",
                    name: request.displayName,
                    suffix: " for leaving the group."
                )
            }
        }
    }

    private func highlightedNameCopy(
        prefix: String,
        name: String,
        suffix: String
    ) -> Text {
        Text(prefix)
            .font(Font.beVietnamPro(14))
            .foregroundStyle(Constants.ContentM)
        + Text(name)
            .font(Font.beVietnamPro(14, weight: .medium))
            .foregroundStyle(Constants.Neutral950)
        + Text(suffix)
            .font(Font.beVietnamPro(14))
            .foregroundStyle(Constants.ContentM)
    }

    /// Figma 4712:2514 — address + USDC check before Approve & send.
    private var payoutAddressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 2) {
                detailRow(
                    label: String(localized: "\(request.displayName)’s address"),
                    value: shortenedAddress
                )
                detailRow(
                    label: String(localized: "Asset"),
                    value: "USDC"
                )
            }
            .background(Constants.White, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(
                "Please double-check with \(request.displayName) to verify whether the address above is correct."
            )
            .font(Font.beVietnamPro(14))
            .tracking(-0.42)
            .foregroundStyle(Constants.ContentB)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
        }
        .padding(3)
        .padding(.top, 0)
        .padding(.bottom, 5)
        .background(Constants.Neutral50, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(Font.beVietnamPro(14, weight: .medium))
                .tracking(-0.28)
                .foregroundStyle(Constants.Neutral950)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var shortenedAddress: String {
        let raw = request.walletAddress ?? ""
        guard raw.count > 10 else {
            return raw.isEmpty ? String(localized: "No wallet linked") : raw
        }
        return "\(raw.prefix(4))...\(raw.suffix(4))"
    }

    private var statusBadge: (asset: String, label: String)? {
        switch request.status {
        case "WAITING_DEPOSIT":
            return (
                "vaultLeaveWaitingCheck",
                String(localized: "Waiting for settlement")
            )
        case "READY":
            return (
                "vaultLeaveReceivedCheck",
                String(localized: "Received")
            )
        default:
            // Stale PAYOUT + dust → treat like READY.
            if !isPayout {
                return (
                    "vaultLeaveReceivedCheck",
                    String(localized: "Received")
                )
            }
            return nil
        }
    }

    private func statusPill(_ badge: (asset: String, label: String)) -> some View {
        HStack(spacing: 6) {
            Image(badge.asset)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 19, height: 19)
                .accessibilityHidden(true)
            Text(badge.label)
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
                .foregroundStyle(Constants.Neutral700)
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Constants.Background, in: Capsule())
    }

    /// Figma Button XL (`4716:2117`): solid `#363636`, fixed height 52 — no glass flexible.
    private var cta: some View {
        Button {
            Task { await handleCta() }
        } label: {
            if isWorking {
                ProgressView()
                    .tint(Constants.White)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            } else {
                Text(ctaTitle)
                    .font(Font.beVietnamPro(17))
                    .tracking(-0.68)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
        }
        .buttonStyle(.plain)
        .background(Constants.Black, in: Capsule())
        .disabled(isWorking)
    }

    private func handleCta() async {
        switch phase {
        case .left:
            dismiss()
        case .request:
            if request.status == "WAITING_DEPOSIT" {
                dismiss()
                return
            }
            let ok = await onConfirm()
            if ok {
                dismiss()
            }
        }
    }

    private func formatUsdc(_ micro: UInt64) -> String {
        let usdc = Double(micro) / 1_000_000
        return "$" + CurrencyFormatter.formatUsdc(usdc)
    }
}

extension Components.Schemas.VaultLeaveRequestDto: @retroactive Identifiable {
    public var id: Int { userId }
}
