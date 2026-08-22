//
//  SearchBar.swift
//  OnePlan
//
//  Created by ken on 25/2/26.
//

import SwiftUI
import UIKit

struct SearchBar: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    let textInputAutocapitalization: TextInputAutocapitalization
    let backgroundColor: Color
    let borderColor: Color?
    let minHeight: CGFloat
    var focusedBinding: FocusState<Bool>.Binding?

    init(
        text: Binding<String>,
        placeholder: LocalizedStringKey = "Search",
        focused: FocusState<Bool>.Binding? = nil,
        textInputAutocapitalization: TextInputAutocapitalization = .never,
        backgroundColor: Color = Constants.Neutral100,
        borderColor: Color? = nil,
        minHeight: CGFloat = 49
    ) {
        _text = text
        self.placeholder = placeholder
        self.focusedBinding = focused
        self.textInputAutocapitalization = textInputAutocapitalization
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.minHeight = minHeight
    }

    init(placeholder: LocalizedStringKey = "Search") {
        _text = .constant("")
        self.placeholder = placeholder
        self.focusedBinding = nil
        self.textInputAutocapitalization = .never
        self.backgroundColor = Constants.Neutral100
        self.borderColor = nil
        self.minHeight = 49
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {

            Image("searchIcon")
                .frame(width: 16, height: 16)

            textField

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Constants.ContentM)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            minHeight: minHeight,
            maxHeight: minHeight,
            alignment: .center
        )
        .background(backgroundColor)
        .overlay {
            if let borderColor {
                RoundedRectangle(cornerRadius: 999)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .cornerRadius(999)
        .contentShape(RoundedRectangle(cornerRadius: 999))
        .simultaneousGesture(
            TapGesture().onEnded {
                triggerHaptic()
            }
        )
    }

    @ViewBuilder
    private var textField: some View {
        let field = TextField(placeholder, text: $text)
            .font(Font.custom("Be Vietnam Pro", size: 14))
            .foregroundColor(Constants.ContentB)
            .textInputAutocapitalization(textInputAutocapitalization)
            .autocorrectionDisabled()
            .submitLabel(.search)
        if let focusedBinding {
            field.focused(focusedBinding)
        } else {
            field
        }
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

#Preview {
    SearchBar()
}
