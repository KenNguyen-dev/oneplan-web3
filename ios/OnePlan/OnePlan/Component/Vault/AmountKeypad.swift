import SwiftUI

/// The numeric keypad used to type a payment amount.
///
/// Digits only, no arithmetic. The caller owns the string so it can format it
/// live and decide what an empty value means.
struct AmountKeypad: View {
    @Binding var digits: String
    /// VND has no minor units, so the decimal key does nothing for it. The key
    /// still occupies its cell, because the grid reads wrong without it.
    var allowsDecimal: Bool = false

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
    ]

    var body: some View {
        VStack(spacing: 5) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { key in
                        digitKey(key)
                    }
                }
            }
            HStack(spacing: 5) {
                // Neither the decimal nor the delete key has a filled
                // background in the design; only the digits do.
                plainKey {
                    Text(".")
                        .font(Font.beVietnamPro(18))
                        .foregroundStyle(Constants.Neutral950)
                } action: {
                    append(".")
                }
                .disabled(!allowsDecimal)
                .opacity(allowsDecimal ? 1 : 0)

                digitKey("0")

                plainKey {
                    Image(systemName: "delete.left")
                        .font(.system(size: 18))
                        .foregroundStyle(Constants.Neutral950)
                } action: {
                    delete()
                }
                .accessibilityLabel("Delete")
            }
        }
    }

    private func digitKey(_ key: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            append(key)
        } label: {
            Text(key)
                .font(Font.beVietnamPro(18, weight: .semibold))
                .tracking(-0.36)
                .foregroundStyle(Constants.Neutral950)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Constants.Background,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private func plainKey<Label: View>(
        @ViewBuilder label: () -> Label,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            label()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
    }

    private func append(_ key: String) {
        if key == "." {
            guard allowsDecimal, !digits.contains(".") else { return }
            digits += digits.isEmpty ? "0." : "."
            return
        }
        // A leading zero would read as "0200000".
        if digits == "0" { digits = key } else { digits += key }
    }

    private func delete() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }
}

#Preview {
    @Previewable @State var digits = "200000"
    VStack {
        Text(digits).font(.largeTitle)
        AmountKeypad(digits: $digits)
            .padding(8)
            .background(Constants.Surface)
    }
    .background(Constants.Background)
}
