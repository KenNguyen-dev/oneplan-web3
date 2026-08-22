import Testing
import UIKit
@testable import OnePlan

/// A `Font.custom` call for a font the bundle never registered does not fail:
/// SwiftUI silently substitutes the system font. Nothing crashes, nothing warns,
/// and the app just stops looking like itself.
///
/// `UIFont(name:size:)` is the honest check — it returns nil for a font iOS
/// cannot resolve.
@Suite("Bundled fonts are registered")
struct FontRegistrationTests {

    /// Every face `Font+BeVietnamPro` can return.
    private static let faces = [
        "BeVietnamPro-Thin",
        "BeVietnamPro-ExtraLight",
        "BeVietnamPro-Light",
        "BeVietnamPro-Regular",
        "BeVietnamPro-Medium",
        "BeVietnamPro-SemiBold",
        "BeVietnamPro-Bold",
        "BeVietnamPro-ExtraBold",
        "BeVietnamPro-Black",
        "BeVietnamPro-Italic",
        "BeVietnamPro-ThinItalic",
        "BeVietnamPro-ExtraLightItalic",
        "BeVietnamPro-LightItalic",
        "BeVietnamPro-MediumItalic",
        "BeVietnamPro-SemiBoldItalic",
        "BeVietnamPro-BoldItalic",
        "BeVietnamPro-ExtraBoldItalic",
        "BeVietnamPro-BlackItalic",
    ]

    @Test("every Be Vietnam Pro face the app asks for resolves")
    func facesResolve() {
        let missing = Self.faces.filter { UIFont(name: $0, size: 14) == nil }
        #expect(missing.isEmpty, "not registered: \(missing.joined(separator: ", "))")
    }

    @Test("the italic face is a different font from the upright one")
    func italicIsDistinct() {
        let upright = UIFont(name: "BeVietnamPro-SemiBold", size: 14)
        let italic = UIFont(name: "BeVietnamPro-SemiBoldItalic", size: 14)
        #expect(upright != nil)
        #expect(italic != nil)
        // Falling back to the system font would make both the same, which is
        // exactly the failure this suite exists to catch.
        #expect(upright?.fontName != italic?.fontName)
    }
}
