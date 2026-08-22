import SwiftUI

extension Font {
    /// Be Vietnam Pro using the correct *named face* per weight.
    ///
    /// Avoids the runtime warning "Unable to update Font Descriptor's weight"
    /// that occurs when calling `.weight()` on a custom font family: Be Vietnam
    /// Pro is shipped as discrete named faces, not a variable font, so CoreText
    /// cannot synthesize a weight trait onto the Regular descriptor.
    static func beVietnamPro(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(beVietnamProFace(for: weight), size: size)
    }

    /// The italic cut of the same family.
    ///
    /// Calling `.italic()` on the regular face does nothing: Be Vietnam Pro is
    /// shipped as discrete named faces, so CoreText has no italic trait to
    /// synthesise, exactly as it has no weight trait. The italic file has to be
    /// named directly.
    static func beVietnamProItalic(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        .custom(beVietnamProItalicFace(for: weight), size: size)
    }

    private static func beVietnamProItalicFace(for weight: Font.Weight) -> String {
        switch weight {
        case .thin:       return "BeVietnamPro-ThinItalic"
        case .ultraLight: return "BeVietnamPro-ExtraLightItalic"
        case .light:      return "BeVietnamPro-LightItalic"
        case .medium:     return "BeVietnamPro-MediumItalic"
        case .semibold:   return "BeVietnamPro-SemiBoldItalic"
        case .bold:       return "BeVietnamPro-BoldItalic"
        case .heavy:      return "BeVietnamPro-ExtraBoldItalic"
        case .black:      return "BeVietnamPro-BlackItalic"
        default:          return "BeVietnamPro-Italic"
        }
        // Same reason as above: Font.Weight is a struct, so this cannot be
        // exhaustive and the default clause is required.
    }

    private static func beVietnamProFace(for weight: Font.Weight) -> String {
        switch weight {
        case .thin:       return "BeVietnamPro-Thin"        // 100
        case .ultraLight: return "BeVietnamPro-ExtraLight"  // 200
        case .light:      return "BeVietnamPro-Light"       // 300
        case .medium:     return "BeVietnamPro-Medium"      // 500
        case .semibold:   return "BeVietnamPro-SemiBold"    // 600
        case .bold:       return "BeVietnamPro-Bold"        // 700
        case .heavy:      return "BeVietnamPro-ExtraBold"   // 800
        case .black:      return "BeVietnamPro-Black"       // 900
        default:          return "BeVietnamPro-Regular"     // 400 — .regular + any future cases
        }
        // NOTE: the `default:` clause is REQUIRED — `Font.Weight` is a struct, not an
        // enum, so the switch cannot be exhaustive. Do not "clean it up" as dead code.
    }
}
