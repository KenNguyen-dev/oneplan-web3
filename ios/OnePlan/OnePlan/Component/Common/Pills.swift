import SwiftUI

struct SummaryPill: View {
    var iconSystemName: String? = nil
    let title: String
    var avatarCount: Int = 0

    var body: some View {
        HStack(spacing: 7) {
            if let iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Constants.ContentB)
                    .frame(width: 22, height: 22)
            } else {
                HStack(spacing: -8) {
                    ForEach(0..<avatarCount, id: \.self) { _ in
                        Image("defaultTripPlaceholder")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(Constants.Surface, lineWidth: 1)
                            }
                    }
                }
                .padding(.trailing, 2)
            }

            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentB)
                .tracking(-0.7)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Constants.Surface.opacity(0.88))
        )
        .overlay {
            Capsule()
                .stroke(Constants.Neutral100, lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 1)
    }
}

struct AppPill: View {
    enum Style {
        case filled
        case outlined
        case compactBlue
    }

    let title: LocalizedStringKey
    let style: Style

    private var backgroundColor: Color {
        switch style {
        case .filled, .compactBlue:
            return Constants.BlueBase
        case .outlined:
            return Constants.Surface
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .filled, .compactBlue:
            return Constants.White
        case .outlined:
            return Constants.ContentB
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .filled, .outlined:
            return 8
        case .compactBlue:
            return 4
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .filled, .outlined:
            return 3
        case .compactBlue:
            return 2
        }
    }

    private var fontSize: CGFloat {
        switch style {
        case .filled, .outlined:
            return 12
        case .compactBlue:
            return 10
        }
    }

    private var trackingValue: CGFloat {
        switch style {
        case .filled, .outlined:
            return -0.6
        case .compactBlue:
            return -0.5
        }
    }

    var body: some View {
        Text(title)
            .font(Font.custom("Be Vietnam Pro", size: fontSize))
            .foregroundStyle(foregroundColor)
            .tracking(trackingValue)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor)
            .clipShape(Capsule())
            .overlay {
                if style == .outlined {
                    Capsule()
                        .stroke(Constants.Neutral100, lineWidth: 1)
                }
            }
    }
}

#Preview("SummaryPill Icon") {
    SummaryPill(
        iconSystemName: "arrow.left.arrow.right",
        title: "395km"
    )
    .padding(16)
    .background(Constants.Surface)
}

#Preview("SummaryPill Avatars") {
    SummaryPill(
        title: "1,200+ visited",
        avatarCount: 3
    )
    .padding(16)
    .background(Constants.Surface)
}

#Preview("AppPill Styles") {
    VStack(alignment: .leading, spacing: 8) {
        AppPill(title: "100,000d - 500,000d", style: .filled)
        AppPill(title: "Open", style: .outlined)
        AppPill(title: "Friends", style: .compactBlue)
    }
    .padding(16)
    .background(Constants.Surface)
}
