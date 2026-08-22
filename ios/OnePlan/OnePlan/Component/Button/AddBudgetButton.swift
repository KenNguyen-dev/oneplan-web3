//
//  SecondaryButton.swift
//  OnePlan
//
//  Created by ken on 24/2/26.
//

import SwiftUI

struct AddBudgetButton: View {
    var title: LocalizedStringKey = "Add budget"
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentB)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 31, style: .continuous)
                        .fill(Constants.White)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 31, style: .continuous)
                        .inset(by: 0.5)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(
                    color: Color.black.opacity(0.07),
                    radius: 12,
                    x: 0,
                    y: 6
                )
                .shadow(
                    color: Color(red: 0.8, green: 0.86, blue: 0.94).opacity(0.35),
                    radius: 18,
                    x: 0,
                    y: 10
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddBudgetButton()
}
