//
//  Chip.swift
//  OnePlan
//
//  Created by ken on 25/2/26.
//

import SwiftUI

struct Chip: View {
    enum Variant {
        case blue
        case green
        case neutral
        case dark

        var backgroundColor: Color {
            switch self {
            case .blue:
                return Constants.BlueBase
            case .green:
                return Constants.Green400
            case .neutral:
                return Constants.Surface
            case .dark:
                return Constants.Black
            }
        }

        var textColor: Color {
            switch self {
            case .neutral:
                return Constants.ContentB
            case .blue, .green, .dark:
                return Constants.White
            }
        }
    }

    let variant: Variant
    let text: String
    let isDisabled: Bool

    init(variant: Variant, text: String, isDisabled: Bool = false) {
        self.variant = variant
        self.text = text
        self.isDisabled = isDisabled
    }

    var body: some View {
        Text(text)
            .font(Font.custom("Be Vietnam Pro", size: 14))
            .foregroundColor(variant.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(isDisabled ? Constants.Neutral200 : variant.backgroundColor)
            .cornerRadius(16)
            .overlay {
                if variant == .neutral && !isDisabled {
                    RoundedRectangle(cornerRadius: 16)
                        .inset(by: -0.5)
                        .stroke(Constants.Neutral100, lineWidth: 1)
                }
            }
    }
}

#Preview {
    VStack(spacing: 12) {
        Chip(variant: .blue, text: "Blue")
        Chip(variant: .green, text: "Green")
        Chip(variant: .neutral, text: "Neutral")
        Chip(variant: .dark, text: "Dark")
        Chip(variant: .blue, text: "Disabled", isDisabled: true)
    }
    .padding()
    .background(Constants.OnSurface)
}
