import SwiftUI

/// Colours the vault screens use that the app's `Constants` does not carry.
///
/// Each is sampled from the design render rather than read off a token, because
/// the design draws these with Apple's Liquid Glass, which lightens whatever
/// tint it is given — so the value in the file is not the value on screen.
enum VaultPalette {
    /// The primary action blue: Scan QR on the card, Done on the expense sheet.
    static let accent = Color(red: 72 / 255, green: 184 / 255, blue: 254 / 255)

    /// The scanner's viewfinder frame.
    static let scanFrame = Color(red: 1, green: 183 / 255, blue: 0)

    /// The header chips.
    ///
    /// Translucent rather than a fixed grey, which is what the design declares
    /// and what makes one value work on two backdrops: over the flat page it
    /// composites to #F5F5F5, and over the receipt's gradient to #CFE1EA. A
    /// solid fill matched the first and became a grey patch stuck on the
    /// second. The separation comes from the shadow either way.
    static let headerChip = Color(white: 213 / 255).opacity(0.35)
}
