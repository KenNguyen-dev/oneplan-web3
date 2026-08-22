import SwiftUI

struct PlanDetailPrevNextStrip: View {
    let onPrev: () -> Void
    let onNext: () -> Void

    init(
        onPrev: @escaping () -> Void = {},
        onNext: @escaping () -> Void = {}
    ) {
        self.onPrev = onPrev
        self.onNext = onNext
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Constants.Neutral100)
                .frame(height: 1)

            HStack(spacing: 16) {
                NavButton(
                    title: "Prev",
                    icon: "arrow.left",
                    action: onPrev
                )

                NavButton(
                    title: "Next",
                    icon: "arrow.right",
                    action: onNext
                )
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
    }
}

private struct NavButton: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Constants.ContentB)
                    .frame(width: 22, height: 22)

                Text(title)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.7)
                    .foregroundStyle(Constants.ContentB)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(Constants.Surface)
            }
            .overlay {
                Capsule()
                    .stroke(Constants.Neutral100, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 0)
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 1)
        }
        .buttonStyle(PrevNextButtonStyle())
    }
}

private struct PrevNextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

#Preview("PlanDetailPrevNextStrip") {
    PlanDetailPrevNextStrip()
        .padding(.vertical, 16)
        .background(Constants.Surface)
}
