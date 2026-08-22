import SwiftUI

struct TagPickerBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedTag: Components.Schemas.ListingTag

    @State private var pendingTag: Components.Schemas.ListingTag = .SOLO

    private let allTags: [Components.Schemas.ListingTag] = [
        .COMPANY, .COUPLES, .FAMILY, .FRIENDS, .SOLO
    ]

    var body: some View {
        VStack(spacing: 12) {
            toolbar

            VStack(spacing: 4) {
                ForEach(allTags, id: \.rawValue) { tag in
                    tagRow(tag)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Background)
        .presentationDetents([.height(390)])
        .presentationDragIndicator(.visible)
        .onAppear {
            pendingTag = selectedTag
        }
    }

    private var toolbar: some View {
        VStack(spacing: 9.8) {
            Color.clear
                .frame(width: 35.2, height: 15.6)

            HStack(alignment: .center) {
                Button {
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Constants.OnSurface)
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Constants.ContentM)
                    }
                    .frame(width: 43, height: 43)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Plan for")
                    .font(Font.custom("Be Vietnam Pro", size: 18))
                    .tracking(-0.72)
                    .foregroundColor(Constants.ContentB)

                Spacer()

                Button {
                    selectedTag = pendingTag
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Constants.BlueBase)
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 43, height: 43)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tagRow(_ tag: Components.Schemas.ListingTag) -> some View {
        let isSelected = pendingTag == tag

        return Button {
            pendingTag = tag
        } label: {
            HStack(spacing: 5) {
                selectionIndicator(isSelected: isSelected)
                    .padding(.leading, 2)
                    .padding(.trailing, 1)

                Text(tag.pickerTitle)
                    .font(Font.custom("SF Compact Rounded", size: 16.6))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.ContentB)
                    .lineLimit(1)

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Constants.Background)
            .cornerRadius(19)
        }
        .buttonStyle(.plain)
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(
                    isSelected
                        ? Color(red: 0, green: 0.53, blue: 1) : .clear
                )
                .overlay(
                    Circle()
                        .stroke(
                            isSelected
                                ? Color.clear
                                : Color(red: 0.78, green: 0.78, blue: 0.80),
                            lineWidth: 1.5
                        )
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private extension Components.Schemas.ListingTag {
    var pickerTitle: String {
        switch self {
        case .COMPANY:
            return String(localized: "Company", comment: "Trip-purpose tag")
        case .COUPLES:
            return String(localized: "Couples", comment: "Trip-purpose tag")
        case .FAMILY:
            return String(localized: "Family", comment: "Trip-purpose tag")
        case .FRIENDS:
            return String(localized: "Friends", comment: "Trip-purpose tag")
        case .SOLO:
            return String(localized: "Solo", comment: "Trip-purpose tag")
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TagPickerBottomSheet(
                selectedTag: .constant(.COMPANY)
            )
        }
}
