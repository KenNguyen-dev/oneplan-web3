//
//  LiquidGlassCompat.swift
//  OnePlan
//
//  Centralizes iOS 26 Liquid Glass usage behind availability checks so the app
//  can deploy to iOS 17.2 while still rendering real Liquid Glass on iOS 26+.
//  Below iOS 26 these helpers fall back to materials / standard control styles.
//

import SwiftUI

// MARK: - Glass effect (View)

extension View {
    /// Applies Liquid Glass on iOS 26+, falling back to a material background below.
    @ViewBuilder
    func glassEffectCompat<S: Shape>(
        in shape: S,
        interactive: Bool = true,
        tint: Color? = nil,
        fallback: Material = .ultraThinMaterial
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(LiquidGlass.make(interactive: interactive, tint: tint), in: shape)
        } else {
            // Below iOS 26 there's no real Liquid Glass. Approximate its depth with a
            // solid surface pill + a soft drop shadow + a hairline rim.
            //
            // The shadow is cast by the OPAQUE `Constants.Surface` shape — never by a
            // `Material`. Shadowing a Material is unstable: a Material is a backdrop
            // blur, not an opaque layer, so when a toolbar re-composites after a
            // push/pop its backdrop isn't ready and the shadow is snapshotted from a
            // dark/opaque frame, producing a hard black halo. An opaque caster is
            // stable across navigation.
            background {
                shape
                    .fill(Constants.Surface)
                    .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
                    .overlay {
                        shape.stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    }
            }
        }
    }

    /// Capsule-shaped variant, matching `.glassEffect()`'s default shape.
    @ViewBuilder
    func glassEffectCompat(
        interactive: Bool = true,
        tint: Color? = nil,
        fallback: Material = .ultraThinMaterial
    ) -> some View {
        glassEffectCompat(in: Capsule(), interactive: interactive, tint: tint, fallback: fallback)
    }
}

/// Builds the iOS 26 `Glass` value. Isolated here so the only `@available(iOS 26)`
/// surface is a single factory rather than every call site.
@available(iOS 26.0, *)
private enum LiquidGlass {
    static func make(interactive: Bool, tint: Color?) -> Glass {
        var glass: Glass = .regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

// MARK: - Glass morph spacing

/// Inter-item spacing for a row of adjacent glass pills inside a
/// `GlassContainerCompat`. Negative values make the pills overlap and *morph*
/// into one continuous shape on iOS 26 — but below iOS 26 the fallback pills are
/// opaque (`Constants.Surface`), so the same negative spacing just overlaps them
/// visibly (e.g. the "Scan by AI" pill colliding with the checkmark button).
/// Returns the morph spacing on iOS 26+ and a non-negative `fallback` below.
@MainActor
func glassMorphSpacing(_ glass: CGFloat, fallback: CGFloat) -> CGFloat {
    if #available(iOS 26.0, *) {
        return glass
    } else {
        return fallback
    }
}

// MARK: - Glass container

/// Wraps content in `GlassEffectContainer` on iOS 26+, passing it through unchanged below.
struct GlassContainerCompat<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Button styles

extension View {
    /// Prominent filled button: `.glassProminent` + flexible sizing on iOS 26+,
    /// a brand-blue capsule that mirrors that look below.
    @ViewBuilder
    func primaryGlassButtonStyle(tint: Color = Constants.BlueBase) -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
                .buttonSizing(.flexible)
                .tint(tint)
        } else {
            buttonStyle(ProminentCapsuleFallbackStyle(tint: tint))
        }
    }

    /// Plain glass button: `.glass` on iOS 26+, `.bordered` below.
    @ViewBuilder
    func glassButtonStyleCompat() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Prominent glass button without flexible sizing: `.glassProminent` on iOS 26+,
    /// the same brand-blue capsule below. Use where the button already controls its width.
    @ViewBuilder
    func glassProminentButtonStyleCompat(tint: Color = Constants.BlueBase) -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
                .tint(tint)
        } else {
            buttonStyle(ProminentCapsuleFallbackStyle(tint: tint))
        }
    }

    /// For buttons that already paint a solid background (e.g. `SecondaryButton`):
    /// overlays interactive glass + flexible sizing on iOS 26+, just fills width below.
    @ViewBuilder
    func filledGlassOverlayCompat() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive())
                .buttonSizing(.flexible)
        } else {
            frame(maxWidth: .infinity)
        }
    }
}

/// Below-iOS-26 stand-in for `.glassProminent`: a solid brand-blue capsule with a
/// soft tinted shadow and a press response, approximating the prominent glass pill.
/// Expects the button's own label to carry its padding / width (the call sites do).
private struct ProminentCapsuleFallbackStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = Constants.BlueBase

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Approximates the extra height `.glassProminent` adds on iOS 26 so the
            // fallback button matches the real glass button's size across versions.
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(isEnabled ? tint : Color.gray.opacity(0.25))
                    .shadow(
                        color: isEnabled ? tint.opacity(0.22) : .clear,
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Stable dismiss (iOS < 26 NavigationStack relayout-loop workaround)

/// Holds a `DismissAction` OUTSIDE the SwiftUI dependency graph.
///
/// Below iOS 26 the `\.dismiss` (and `\.openURL`) environment *actions* get a fresh
/// identity on every `NavigationStack` relayout. A heavy view sitting in a pushed
/// stack that reads `@Environment(\.dismiss)` re-renders on every churn → rebuilds its
/// children / navigation destinations → triggers another relayout → invalidates
/// `\.dismiss` again → infinite re-render loop that pegs the main thread (the app
/// appears frozen). Reading dismiss through this holder keeps the heavy `body` off the
/// dependency graph, so it no longer re-renders when dismiss's identity changes.
///
/// Usage: `@State private var stableDismiss = StableDismiss()`, attach
/// `.captureStableDismiss(stableDismiss)` once in the body, and call `stableDismiss()`
/// where you would have called `dismiss()`.
@MainActor
final class StableDismiss {
    fileprivate var action: DismissAction?
    func callAsFunction() { action?() }
}

extension View {
    /// Captures the current `\.dismiss` into `holder` via a hidden, childless sibling
    /// so the host view does not depend on dismiss's (churning) identity.
    func captureStableDismiss(_ holder: StableDismiss) -> some View {
        background(StableDismissCapture(holder: holder))
    }
}

private struct StableDismissCapture: View {
    @Environment(\.dismiss) private var dismiss
    let holder: StableDismiss
    var body: some View {
        // This tiny leaf is the ONLY thing that re-renders when `\.dismiss`'s identity
        // churns; keep the holder current. `holder` is a plain (un-observed) reference,
        // so writing it here creates no SwiftUI dependency and the leaf has no children
        // to cascade a relayout — the loop is broken.
        holder.action = dismiss
        return Color.clear.frame(width: 0, height: 0)
    }
}

// MARK: - Toolbar shared background

extension ToolbarContent {
    /// Hides the shared Liquid Glass background of toolbar items on iOS 26+; no-op below.
    @ToolbarContentBuilder
    func sharedBackgroundHiddenCompat() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
