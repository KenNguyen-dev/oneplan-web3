import SwiftUI

/// Shared chrome for end-trip consensus screens (Figma Back + Go back).
enum TripEndConsensusChrome {
    /// Arrow + "Back" pills — same treatment as vault light pages.
    struct BackHeader: View {
        var onBack: () -> Void

        var body: some View {
            HStack(spacing: 5) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Constants.Neutral900)
                        .frame(width: 32, height: 32)
                }
                .vaultHeaderChip()
                .accessibilityLabel("Back")

                Button(action: onBack) {
                    Text("Back")
                        .font(Font.beVietnamPro(15))
                        .tracking(-0.3)
                        .foregroundStyle(Constants.Neutral900)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                }
                .vaultHeaderChip()

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    /// Full-width black capsule used on waiting / denied.
    struct GoBackButton: View {
        var title: LocalizedStringKey = "Go back"
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(Font.beVietnamPro(17))
                    .tracking(-0.68)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Constants.Black, in: Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// Orange cube cluster — Figma waiting glyph.
    static var waitingGlyph: some View {
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

    /// Soft top wash — waiting uses sky, denied uses pink.
    static func statusGradient(kind: StatusWash) -> some View {
        let stops: [Gradient.Stop]
        switch kind {
        case .waiting:
            stops = [
                .init(color: Color(red: 0.706, green: 0.875, blue: 1), location: 0),
                .init(color: Color(red: 0.984, green: 0.925, blue: 0.843), location: 0.514),
                .init(color: Constants.Background, location: 1),
            ]
        case .denied:
            stops = [
                .init(color: Color(red: 1, green: 0.706, blue: 0.714), location: 0),
                .init(color: Color(red: 0.984, green: 0.843, blue: 0.843), location: 0.514),
                .init(color: Constants.Background, location: 1),
            ]
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    enum StatusWash {
        case waiting
        case denied
    }
}
