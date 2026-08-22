import SwiftUI

/// Shared design tokens used across the app.
/// Keep values centralized here to make visual updates consistent.
enum Constants {
    // MARK: - Surface & Background
    /// Primary surface color for cards, sheets, and containers.
    static let Surface: Color = Color(UIColor(red: 1, green: 1, blue: 1, alpha: 1))
    /// Subtle on-surface tone used for light fills and overlays.
    static let OnSurface: Color = Color(UIColor(red: 0.91, green: 0.91, blue: 0.91, alpha: 1))
    /// App-level background color.
    static let Background: Color = Color(red: 0.97, green: 0.97, blue: 0.97)

    // MARK: - Base Colors
    static let White: Color = Color(.white)
    static let Black: Color = Color(red: 0.21, green: 0.21, blue: 0.21)
    
    static let Secondary: Color = Color(red: 0.88, green: 0.15, blue: 0.14)

    // MARK: - Content Colors
    /// Primary content (high emphasis text/icons).
    static let ContentB: Color = Color(UIColor(red: 0.21, green: 0.21, blue: 0.21, alpha: 1))
    /// Secondary content (medium emphasis text/icons).
    static let ContentM: Color = Color(red: 0.6, green: 0.6, blue: 0.6)
    /// Tertiary content (low emphasis text/icons).
    static let ContentL: Color = Color(UIColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1))

    // MARK: - Semantic Colors
    /// Warning or destructive emphasis color.
    static let Warning500: Color = Color(red: 1, green: 0.35, blue: 0.12)
    /// Positive accent shades.
    static let Green100: Color = Color(red: 0.87, green: 0.97, blue: 0.93)
    static let Green400: Color = Color(red: 0.19, green: 0.77, blue: 0.55)
    static let Green500: Color = Color(red: 0.05, green: 0.62, blue: 0.43)

    // MARK: - Brand & Accent Colors
    static let BlueBase: Color = Color(red: 0.2, green: 0.36, blue: 1)
    /// Blue accent with 10% opacity, useful for selected/highlighted backgrounds.
    static let BlueAlpha10: Color = Color(red: 0.28, green: 0.42, blue: 1).opacity(0.1)
    static let BlueAlpha16: Color = Color(red: 0.28, green: 0.42, blue: 1).opacity(0.16)
    static let Purple500: Color = Color(red: 0.56, green: 0.38, blue: 0.98)

    // MARK: - Neutral Palette
    static let Neutral50: Color = Color(red: 0.97, green: 0.97, blue: 0.97)
    static let Neutral100: Color = Color(red: 0.91, green: 0.91, blue: 0.91)
    static let Neutral200: Color = Color(red: 0.87, green: 0.87, blue: 0.87)
    static let Neutral400: Color = Color(red: 0.68, green: 0.68, blue: 0.68)
    static let Neutral600: Color = Color(red: 0.53, green: 0.53, blue: 0.53)
    static let Neutral700: Color = Color(red: 0.48, green: 0.48, blue: 0.48)
    static let Neutral900: Color = Color(red: 0.33, green: 0.33, blue: 0.33)
    static let Neutral950: Color = Color(red: 0.21, green: 0.21, blue: 0.21)

    // MARK: - Utility Colors
    /// Soft helper text tone.
    static let textSoft400: Color = Color(red: 0.68, green: 0.68, blue: 0.68)
    /// Divider and stroke color for subtle separators.
    static let DividerStroke: Color = Color(UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1))
}
