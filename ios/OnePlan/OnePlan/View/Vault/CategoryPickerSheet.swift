import SwiftUI

/// Picks the expense category for a vault payment.
///
/// Lists `CategoryChip.Category.allCases`, so it can never drift from what the
/// API accepts: adding a server category makes it appear here automatically.
struct CategoryPickerSheet: View {
    @Binding var selected: CategoryChip.Category
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Constants.Neutral200)
                .frame(width: 35, height: 5)
                .padding(.top, 12)

            Text("Categories")
                .font(Font.beVietnamPro(20))
                .tracking(-0.4)
                .foregroundStyle(Constants.ContentB)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(CategoryChip.Category.allCases, id: \.self) { category in
                        row(for: category)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Surface)
    }

    private func row(for category: CategoryChip.Category) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selected = category
            onDismiss()
        } label: {
            HStack(spacing: 10) {
                CategoryIcon(category: category, size: 43)

                Text(category.title)
                    .font(Font.beVietnamPro(16))
                    .foregroundStyle(Constants.ContentB)

                Spacer(minLength: 0)

                if selected == category {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Constants.BlueBase)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == category ? [.isSelected] : [])
    }
}

#Preview {
    @Previewable @State var selected = CategoryChip.Category.coffee
    CategoryPickerSheet(selected: $selected)
}
