import SwiftUI

struct EditInfoRow: View {
    let title: LocalizedStringKey
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(value)
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundStyle(valueColor ?? Constants.ContentB)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct EditInfoTextFieldRow: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)

            Spacer(minLength: 8)

            TextField(placeholder, text: $value)
                .font(Font.beVietnamPro(16, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Constants.ContentB)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
