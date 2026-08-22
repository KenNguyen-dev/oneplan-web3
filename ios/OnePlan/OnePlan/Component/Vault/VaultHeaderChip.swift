import SwiftUI

/// The pill treatment the vault screens share for their header controls.
///
/// Two variants, because the same chip sits on two very different backdrops.
///
/// On a page it is a flat fill: the design's chips are #F5F5F5 on a #F7F7F7
/// page — two units apart — so what separates them is the shadow, not the
/// colour. A translucent material there picks up the page and lands somewhere
/// else, which reads as the background being wrong.
///
/// Over a camera feed the opposite holds. The design's declared fill is six
/// percent grey, which only reads when the picture shows through, and its dark
/// text would disappear against video — so that variant is translucent with
/// light content.
struct VaultHeaderChip: ViewModifier {
    var cornerRadius: CGFloat = 16
    /// Over a camera feed the same chip has to be translucent, or it becomes a
    /// white block punched out of the picture. The design's own fill is six
    /// percent grey, which only reads at all when the backdrop shows through.
    var overCamera: Bool = false

    func body(content: Content) -> some View {
        if overCamera {
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .environment(\.colorScheme, .dark)
        } else {
            content
                .background(VaultPalette.headerChip)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 4)
        }
    }

}

extension View {
    /// Applies the vault header pill treatment.
    ///
    /// `cornerRadius` defaults to the design's 16, which turns a 32pt square
    /// into a circle without needing a separate shape.
    func vaultHeaderChip(
        cornerRadius: CGFloat = 16,
        overCamera: Bool = false
    ) -> some View {
        modifier(VaultHeaderChip(cornerRadius: cornerRadius, overCamera: overCamera))
    }
}
