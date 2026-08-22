//
//  ExpandableGlassEffect.swift
//  OnePlan
//
//  Originally created by Balaji Venkatesh (Kavsoft).
//  Adapted for OnePlan.
//

import SwiftUI

struct ExpandableGlassEffect<Content: View, Label: View>: View, Animatable {
    var alignment: Alignment
    var progress: CGFloat
    var labelSize: CGSize = .init(width: 55, height: 55)
    var cornerRadius: CGFloat = 30
    @ViewBuilder var content: Content
    @ViewBuilder var label: Label
    /// View Properties
    @State private var contentSize: CGSize = .zero

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GlassContainerCompat {
            glassCard
        }
        .scaleEffect(
            x: 1 - (blurProgress * 0.5),
            y: 1 + (blurProgress * 0.35),
            anchor: scaleAnchor
        )
        .offset(y: offset * blurProgress)
    }

    @ViewBuilder
    private var glassCard: some View {
        let widthDiff = contentSize.width - labelSize.width
        let heightDiff = contentSize.height - labelSize.height

        let rWidth = widthDiff * contentOpacity
        let rHeight = heightDiff * contentOpacity

        ZStack(alignment: alignment) {
            content
                .compositingGroup()
                .scaleEffect(contentScale)
                .blur(radius: 14 * blurProgress)
                .opacity(contentOpacity)
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: { newValue in
                    contentSize = newValue
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    width: labelSize.width + rWidth,
                    height: labelSize.height + rHeight
                )
                // Opacity 0 does NOT disable hit testing — without this the
                // invisible expanded content competes for touches while collapsed.
                .allowsHitTesting(progress > 0.95)

            label
                .compositingGroup()
                .blur(radius: 14 * blurProgress)
                .opacity(1 - labelOpacity)
                .frame(width: labelSize.width, height: labelSize.height)
                // The label is a UIViewRepresentable on top of the ZStack; its
                // UIKit view keeps receiving touches even at opacity 0, stealing
                // taps from the expanded content underneath.
                .allowsHitTesting(progress < 0.05)
        }
        .compositingGroup()
        .clipShape(.rect(cornerRadius: cornerRadius))
        // Non-interactive: `.interactive()` glass adds its own touch response on
        // iOS 26, which competes with the UISegmentedControl's touch tracking.
        .glassEffectCompat(in: RoundedRectangle(cornerRadius: cornerRadius), interactive: false)
    }

    var labelOpacity: CGFloat {
        min(progress / 0.35, 1)
    }

    var contentOpacity: CGFloat {
        max(progress - 0.35, 0) / 0.65
    }

    var contentScale: CGFloat {
        let minAspectScale = min(labelSize.width / contentSize.width, labelSize.height / contentSize.height)

        return minAspectScale + (1 - minAspectScale) * progress
    }

    var blurProgress: CGFloat {
        return progress > 0.5 ? (1 - progress) / 0.5 : progress / 0.5
    }

    var offset: CGFloat {
        switch alignment {
        case .bottom, .bottomLeading, .bottomTrailing: return -80
        case .top, .topLeading, .topTrailing: return 80
        default: return -10
        }
    }

    var scaleAnchor: UnitPoint {
        switch alignment {
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
    }
}
