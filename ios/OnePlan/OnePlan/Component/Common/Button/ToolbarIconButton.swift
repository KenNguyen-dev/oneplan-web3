//
//  ToolbarIconButton.swift
//  OnePlan
//
//  Created by Codex on 2026-04-11.
//

import SwiftUI
import UIKit

struct ToolbarIconButton: View {
    let systemName: String
    var foregroundColor: Color = Constants.ContentB
    var horizontalPadding: CGFloat = 11
    var verticalPadding: CGFloat = 11
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button {
                    triggerHaptic()
                    action()
                } label: {
                    icon
                }
            } else {
                icon
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            triggerHaptic()
                        }
                    )
            }
        }
    }

    private var icon: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .glassEffectCompat(in: Circle())
            .contentShape(.circle)
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
