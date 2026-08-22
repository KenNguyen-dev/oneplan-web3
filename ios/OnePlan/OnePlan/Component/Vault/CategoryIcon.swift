import SwiftUI

/// Draws a category using the illustration the design ships for it.
///
/// Two categories have no illustration yet — the mockup's last rows sit outside
/// the sheet, so Figma renders one clipped and one blank — and those fall back
/// to the emoji rather than to a blank square.
struct CategoryIcon: View {
    let category: CategoryChip.Category
    var size: CGFloat = 43

    var body: some View {
        if category.iconAsset.isEmpty {
            Text(category.emoji)
                .font(.system(size: size * 0.62))
                .frame(width: size, height: size)
        } else {
            Image(category.iconAsset)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }
}
