import SwiftUI

/// Glass X control shared by trip-wallet sheets (Figma toolbar Button Group).
struct TripWalletSheetCloseButton: View {
    var action: () -> Void

    private static let icon = Color(red: 0x72 / 255, green: 0x72 / 255, blue: 0x72 / 255)

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Self.icon)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .frame(height: 44)
        .glassEffectCompat(in: Capsule(style: .continuous))
        .contentShape(Capsule())
    }
}

/// Screen 1 — full “How your money is held?” (Figma `4251:16215` / `4251:16338`).
/// Opened from “See how your money is held” as a scrollable bottom sheet.
struct HowMoneyIsHeldView: View {
    var onClose: () -> Void = {}

    private static let ink = Color(red: 0x36 / 255, green: 0x36 / 255, blue: 0x36 / 255)
    private static let body = Color(red: 0x54 / 255, green: 0x54 / 255, blue: 0x54 / 255)

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                TripWalletSheetCloseButton(action: onClose)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How your money is held?")
                        .font(Font.beVietnamPro(28))
                        .tracking(-1.96)
                        .foregroundStyle(Self.ink)

                    HowMoneyIsHeldDocument(
                        sections: HowMoneyIsHeldCopy.fullSections,
                        bodyColor: Self.body,
                        titleColor: Self.body
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.White)
    }
}

/// Shared section renderer for the full money-held document.
struct HowMoneyIsHeldDocument: View {
    let sections: [HowMoneyIsHeldCopy.Section]
    var bodyColor: Color = Constants.Neutral900
    var titleColor: Color = Constants.Neutral950

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 0) {
                    if let title = section.title {
                        Text(title)
                            .font(Font.beVietnamPro(15))
                            .tracking(-0.6)
                            .foregroundStyle(titleColor)
                            .padding(.bottom, 4)
                    }

                    ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(Font.beVietnamPro(15))
                            .tracking(-0.6)
                            .foregroundStyle(bodyColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 8)
                    }

                    if !section.bullets.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .font(Font.beVietnamPro(15))
                                    Text(bullet)
                                        .font(Font.beVietnamPro(15))
                                        .tracking(-0.6)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundStyle(bodyColor)
                            }
                        }
                        .padding(.leading, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    Color.black.opacity(0.3)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            HowMoneyIsHeldView()
                .presentationDetents([.large])
                .presentationCornerRadius(38)
        }
}
