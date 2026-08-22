//
//  PrimaryButton.swift
//  pocket-check
//
//  Created by GitHub Copilot.
//

import SwiftUI

/// A reusable primary action button used across the app.
struct PrimaryButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: LocalizedStringKey
    var tint: Color = Constants.BlueBase
    /// When false, hugs content (Figma Button XL) instead of stretching full width.
    var fillsWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            action()
        } label: {
            Text(title)
                .font(fillsWidth ? .system(size: 16) : Font.beVietnamPro(15))
                .tracking(fillsWidth ? 0 : -0.75)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.vertical, fillsWidth ? 7.5 : 12)
                .padding(.horizontal, fillsWidth ? 16 : 20)
        }
        .foregroundColor(isEnabled ? .white : .gray)
        .modifier(PrimaryButtonChrome(fillsWidth: fillsWidth, tint: tint))
        .fixedSize(horizontal: !fillsWidth, vertical: true)
    }
}

private struct PrimaryButtonChrome: ViewModifier {
    let fillsWidth: Bool
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if fillsWidth {
            content.primaryGlassButtonStyle(tint: tint)
        } else {
            // Figma Button XL: hug content + solid capsule — skip `.glassProminent`
            // / flexible sizing, which inflate height past `py-12`.
            content.buttonStyle(CompactCapsuleButtonStyle(tint: tint))
        }
    }
}

/// Compact Figma Button XL stand-in: label already owns `px-20` / `py-12`.
private struct CompactCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule(style: .continuous)
                    .fill(isEnabled ? tint : Color.gray.opacity(0.25))
                    .shadow(
                        color: isEnabled ? Color.black.opacity(0.12) : .clear,
                        radius: 4,
                        x: 0,
                        y: 1
                    )
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PrimaryButton_Previews: PreviewProvider {
    static var previews: some View {
        PrimaryButton(title: "Be your own millionaire", action: {})
            .previewLayout(.sizeThatFits)
            .padding()
//            .disabled(true)
    }
}
