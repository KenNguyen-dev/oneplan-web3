//
//  SecondaryButton.swift
//  pocket-check
//
//  Created by GitHub Copilot.
//

import SwiftUI

/// A reusable secondary action button used across the app.
/// Supports variants: light, dark, and danger.
struct SecondaryButton: View {
    enum Variant {
        case light
        case dark
        case danger
    }

    /// Position for an optional icon
    enum IconPosition {
        case leading
        case trailing
    }

    let title: LocalizedStringKey
    let variant: Variant
    let icon: Image?
    let iconPosition: IconPosition
    let action: () -> Void

    init(title: LocalizedStringKey,
        variant: Variant = .danger,
        icon: Image? = nil,
        iconPosition: IconPosition = .leading,
        action: @escaping () -> Void) {
        self.title = title
        self.variant = variant
        self.icon = icon
        self.iconPosition = iconPosition
        self.action = action
    }

    /// Convenience initializer that accepts an SF Symbol name (system image).
    /// This initializer requires the `systemImageName` label (no default) to avoid
    /// ambiguity with the primary initializer that has defaulted parameters.
    init(title: LocalizedStringKey,
         variant: Variant = .danger,
         systemImageName: String?,
         iconPosition: IconPosition = .leading,
         action: @escaping () -> Void) {
        // Create the system image as a template so it picks up the button's foreground tint
        self.init(title: title,
                  variant: variant,
                  icon: systemImageName.map { Image(systemName: $0).renderingMode(.template) },
                  iconPosition: iconPosition,
                  action: action)
    }

    private var bgColor: Color {
        switch variant {
        case .light:
            return Color(UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1))
        case .dark:
            return Color(UIColor(red: 0.21, green: 0.21, blue: 0.21, alpha: 1))
        case .danger:
            return Color(UIColor(red: 1, green: 0.28, blue: 0.3, alpha: 1))
        }
    }

    private var foreground: Color {
        switch variant {
        case .light:
            return Color(.label)
        case .dark, .danger:
            return .white
        }
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            action()
        } label: {
            HStack {
                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let icon = icon, iconPosition == .leading {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }

                    Text(title)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .padding(.vertical, 14)

                    if let icon = icon, iconPosition == .trailing {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                }
                .padding(.horizontal, 12)

                Spacer(minLength: 0)
            }
        }
        .background(bgColor)
        .foregroundColor(foreground)
        .cornerRadius(.infinity)
        .filledGlassOverlayCompat()
    }
}

struct SecondaryButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            SecondaryButton(title: "Light Variant", variant: .light, action: {})
                .previewLayout(.sizeThatFits)
                .padding()

            SecondaryButton(title: "Dark Variant", variant: .dark, action: {})
                .previewLayout(.sizeThatFits)
                .padding()

            SecondaryButton(title: "Danger Variant", variant: .danger, action: {})
                .previewLayout(.sizeThatFits)
                .padding()

            // With icons
            SecondaryButton(title: "Archive", variant: .light, icon: Image(systemName: "archivebox"), iconPosition: .leading, action: {})
                .previewLayout(.sizeThatFits)
                .padding()

            SecondaryButton(title: "Delete", variant: .danger, icon: Image(systemName: "trash"), iconPosition: .leading, action: {})
                .previewLayout(.sizeThatFits)
                .padding()

            // Using the convenience initializer with SF Symbol name string
            SecondaryButton(title: "Delete (sys)", variant: .danger, systemImageName: "trash", action: {})
                .previewLayout(.sizeThatFits)
                .padding()

            // Comparison row
            HStack(spacing: 12) {
                SecondaryButton(title: "Delete", variant: .danger, icon: Image(systemName: "trash"), iconPosition: .leading, action: {})
                SecondaryButton(title: "Archive", variant: .light, icon: Image(systemName: "archivebox"), iconPosition: .leading, action: {})
                PrimaryButton(title: "Confirm", action: {})
            }
            .padding()
        }
        .previewLayout(.sizeThatFits)
    }
}
