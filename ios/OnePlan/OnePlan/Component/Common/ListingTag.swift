import SwiftUI

struct ListingTag: View {
    let tag: Components.Schemas.ListingTag

    var body: some View {
        Text(tag.displayName)
            .font(Font.custom("Be Vietnam Pro", size: 14))
            .foregroundStyle(tag.foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tag.backgroundColor)
            .clipShape(Capsule())
    }
}

private extension Components.Schemas.ListingTag {
    var displayName: String {
        rawValue.capitalized
    }

    var foregroundColor: Color {
        switch self {
        case .SOLO:
            return Color(red: 10 / 255, green: 129 / 255, blue: 148 / 255)
        case .FRIENDS:
            return Color(red: 51 / 255, green: 92 / 255, blue: 1)
        case .COUPLES:
            return Color(red: 240 / 255, green: 82 / 255, blue: 82 / 255)
        case .FAMILY:
            return Color(red: 227 / 255, green: 160 / 255, blue: 8 / 255)
        case .COMPANY:
            return Color(red: 1, green: 90 / 255, blue: 31 / 255)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .SOLO:
            return Color(red: 206 / 255, green: 1, blue: 1)
        case .FRIENDS:
            return Color(red: 71 / 255, green: 108 / 255, blue: 1, opacity: 0.16)
        case .COUPLES:
            return Color(red: 252 / 255, green: 232 / 255, blue: 232 / 255)
        case .FAMILY:
            return Color(red: 253 / 255, green: 246 / 255, blue: 178 / 255)
        case .COMPANY:
            return Color(red: 254 / 255, green: 236 / 255, blue: 220 / 255)
        }
    }
}

#Preview {
    HStack(spacing: 4) {
        ListingTag(tag: .COUPLES)
        ListingTag(tag: .FRIENDS)
        ListingTag(tag: .FAMILY)
        ListingTag(tag: .SOLO)
        ListingTag(tag: .COMPANY)
    }
    .padding(16)
    .background(Constants.White)
}
