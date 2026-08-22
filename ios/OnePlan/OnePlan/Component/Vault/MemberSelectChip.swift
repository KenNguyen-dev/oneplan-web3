import SwiftUI

/// One avatar in the "Paid by" or "Share with" rows of the vault expense sheet.
///
/// Takes its selected tint from the caller because the two rows are deliberately
/// different colours in the design: orange for who paid, blue for who shares.
struct MemberSelectChip: View {
    let name: String
    let avatarUrl: String?
    /// Drawn instead of a remote image for the "Group" and "All" entries.
    var systemImage: String?
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 5) {
                avatar
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    // Stroke on the 36pt frame (not padding(-3)) so the ring
                    // stays concentric with the avatar — matches EditExpenseShareAllChip.
                    .overlay {
                        Circle()
                            .stroke(isSelected ? tint : .clear, lineWidth: 2)
                    }

                Text(name)
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.28)
                    .foregroundStyle(isSelected ? tint : Constants.ContentM)
                    .lineLimit(1)
                    .frame(maxWidth: 52)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var avatar: some View {
        if let systemImage {
            ZStack {
                Circle()
                    .fill(Constants.Black)
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Constants.White)
            }
            .frame(width: 36, height: 36)
        } else if let avatarUrl, let url = URL(string: avatarUrl) {
            CachedRemoteImage(url: url, targetSize: CGSize(width: 36, height: 36)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(Constants.Neutral200)
            }
        } else {
            ZStack {
                Circle().fill(Constants.Neutral200)
                Text(String(name.prefix(1)).uppercased())
                    .font(Font.beVietnamPro(14))
                    .foregroundStyle(Constants.ContentM)
            }
        }
    }
}
