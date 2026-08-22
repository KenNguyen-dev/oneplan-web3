//
//  MemberExpenseBreakdown.swift
//  OnePlan
//

import SwiftUI

struct MemberExpenseBreakdown: View {
    let member: MemberBreakdownDto
    let isCurrentUser: Bool
    let homeCurrency: Currency?
    let localCurrency: Currency?

    @State private var convertedShareText: String?
    @State private var conversionTask: Task<Void, Never>?

    private var homeSymbol: String { homeCurrency?.symbol ?? "đ" }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            avatar

            Text(isCurrentUser ? "You" : member.displayName)
                .font(Font.beVietnamPro(16, weight: .medium))
                .foregroundColor(Constants.ContentB)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .center, spacing: 3) {
                    Text(homeSymbol)
                        .font(Font.custom("Be Vietnam Pro", size: 18))
                        .foregroundColor(Constants.ContentL)

                    Text(CurrencyFormatter.formatWhole(member.totalShare))
                        .font(Font.custom("Be Vietnam Pro", size: 18))
                        .foregroundColor(Constants.ContentB)

                    if (homeCurrency?.decimalPlaces ?? 0) > 0 {
                        Text(CurrencyFormatter.formatDecimal(member.totalShare))
                            .font(Font.custom("Be Vietnam Pro", size: 18))
                            .foregroundColor(Constants.ContentL)
                    }
                }

                convertedShareView
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(Constants.Surface)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.06), radius: 8.95, x: 0, y: 0)
        .task(id: localCurrency) {
            refreshConvertedShare()
        }
        .onChange(of: member.totalShare) { _, _ in
            refreshConvertedShare()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        CachedRemoteImage(
            url: member.avatarUrl.flatMap(URL.init(string:)),
            targetSize: CGSize(width: 52, height: 52)
        ) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Image("avatarPlaceholder")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var convertedShareView: some View {
        if let convertedShareText {
            Text(convertedShareText)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.trailing)
                .foregroundColor(Constants.ContentM)
        } else {
            Color.clear.frame(height: 18)
        }
    }

    private func refreshConvertedShare() {
        conversionTask?.cancel()

        guard let home = homeCurrency,
              let local = localCurrency,
              local != home
        else {
            convertedShareText = nil
            return
        }

        if let cached = ExchangeRateService.shared.cachedRate(from: home, to: local) {
            convertedShareText = formatConverted(member.totalShare * cached, in: local)
            return
        }

        let amount = member.totalShare
        conversionTask = Task { @MainActor in
            do {
                let rate = try await ExchangeRateService.shared.rate(from: home, to: local)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    convertedShareText = formatConverted(amount * rate, in: local)
                }
            } catch {
                // Silent — leave reserved space empty.
            }
        }
    }

    private func formatConverted(_ value: Double, in cur: Currency) -> String {
        let whole = CurrencyFormatter.formatWhole(value)
        let decimal = cur.decimalPlaces > 0 ? CurrencyFormatter.formatDecimal(value) : ""
        return "~\(whole)\(decimal) \(cur.rawValue)"
    }
}
