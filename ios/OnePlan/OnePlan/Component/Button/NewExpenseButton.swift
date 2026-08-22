//
//  PrimaryButton.swift
//  OnePlan
//
//  Created by ken on 24/2/26.
//

import SwiftUI

struct NewExpenseButton: View {
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text("New expense")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.White)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                .background(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(
                                color: Color(red: 0.28, green: 0.42, blue: 1).opacity(
                                    0.19
                                ),
                                location: 0.00
                            ),
                            Gradient.Stop(
                                color: Color(red: 0, green: 0.31, blue: 0.85),
                                location: 1.00
                            ),
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 0),
                        endPoint: UnitPoint(x: 0.5, y: 1)
                    )
                )
                .cornerRadius(31)
                .shadow(
                    color: Color(red: 0.58, green: 0.82, blue: 1).opacity(0.25),
                    radius: 5.7,
                    x: 0,
                    y: 13
                )
                .shadow(
                    color: Color(red: 0.39, green: 0.57, blue: 1).opacity(0.39),
                    radius: 3.05,
                    x: 0,
                    y: 3
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 31)
                        .inset(by: 0.75)
                        .stroke(.white, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NewExpenseButton()
}
