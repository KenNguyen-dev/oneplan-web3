//
//  FreeTrialView.swift
//  OnePlan
//

import StoreKit
import SwiftUI

struct FreeTrialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(StoreManager.self) private var storeManager

    private let expiryDate: Date
    private let onClose: (() -> Void)?

    @State private var monthlyProduct: Product?
    @State private var isLoadingProduct = true

    private let benefits: [FreeTrialBenefit] = [
        .init(
            symbol: "icloud.and.arrow.up",
            title: "Upload plans on market"
        ),
        .init(
            symbol: "location.north.fill",
            title: "Unlimited planning trips"
        ),
        .init(symbol: "receipt", title: "Split bill by AI"),
        .init(
            symbol: "play.rectangle.fill",
            title: "Extract pins by video",
            detail: "10 videos/week"
        ),
        .init(symbol: "signpost.right.fill", title: "Trip insights"),
    ]

    init(
        expiryDate: Date = Date().addingTimeInterval(60 * 60),
        onClose: (() -> Void)? = nil
    ) {
        self.expiryDate = expiryDate
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                hero

                VStack(spacing: 16) {
                    benefitsCard

                    countdownSection

                    purchaseSection

                    footer
                        .padding(.top, 32)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 54)
            }
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack(alignment: .top) {
                Constants.White

                topBlurBackground
            }
            .ignoresSafeArea()
            // Clip the blurred glow to the screen bounds and flatten it into a
            // single layer. Without this, the 60pt blur halo paints beyond the
            // view frame and sweeps across the bottom during the cover's
            // slide-down dismiss (the "blue leaking onto Home" artifact).
            .compositingGroup()
            .clipped()
        }
        .ignoresSafeArea(edges: .top)
        .task {
            await loadMonthlyProduct()
        }
        .task {
            // Auto-dismiss when the limited-time offer window elapses, so the
            // screen never advertises "1 month free / No Payment today" past the
            // advertised deadline. Use do/catch (not try?): a manual dismiss
            // cancels this task and Task.sleep throws CancellationError — we must
            // NOT fall through to close() in that case.
            let remaining = expiryDate.timeIntervalSinceNow
            // Already past at appear: don't flash-close (the presentation gate
            // already prevents showing an expired offer); just don't schedule.
            guard remaining > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return   // cancelled because the view was dismissed — do NOT close
            }
            close()      // deadline genuinely elapsed while the screen was open
        }
        .onAppear {
            AnalyticsClient.shared.track(.SUBSCRIPTION_VIEWED)
        }
    }

    // The English hero reads "Planning trip · with · NO limits". Vietnamese drops
    // the standalone connector so it reads "Lên kế hoạch chuyến đi · KHÔNG giới hạn".
    private var showsConnector: Bool {
        locale.language.languageCode?.identifier != "vi"
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: -1) {
                Text("Planning trip")
                if showsConnector {
                    Text("with")
                }
                Text("NO limits")
                    .font(.custom("BeVietnamPro-BlackItalic", size: 36))
                    .italic()
                    .padding(.bottom, 12)

                Text("1 month free")
                    .font(.beVietnamPro(20, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Constants.White)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Constants.BlueBase, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Constants.White, lineWidth: 1.4)
                    }
            }
            .font(.beVietnamPro(36, weight: .semibold))
            .tracking(-0.72)
            .lineSpacing(-1.08)
            .lineLimit(1)
            // Longer localizations (e.g. Vietnamese) exceed the English width
            // this hero was designed for. Scale each headline line down to fit
            // the text column instead of clipping under the scooter, keeping
            // the line count — and therefore the hero height — unchanged.
            .minimumScaleFactor(0.5)
            .foregroundStyle(Constants.White)
            .frame(maxWidth: 250, alignment: .leading)
            .padding(.leading, 24)
            .padding(.top, 103)

            Image("freeTrialScooter")
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 206)
                .offset(x: 211, y: 86)
                .accessibilityHidden(true)

            ToolbarIconButton(
                systemName: "xmark",
                horizontalPadding: 10,
                verticalPadding: 10,
                action: close
            )
            .accessibilityLabel("Close")
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 24)
            .padding(.top, 60)
        }
        .frame(height: 288)
        .clipped()
    }

    private var topBlurBackground: some View {
        Circle()
            .fill(
                Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1))
            )
            .frame(width: 500, height: 800)
            .blur(radius: 60)
            .offset(y: -340)
            .allowsHitTesting(false)
    }

    private var benefitsCard: some View {
        VStack(spacing: 16) {
            ForEach(Array(benefits.enumerated()), id: \.element.id) {
                index, benefit in
                AnimatedFreeTrialBenefitRow(
                    index: index,
                    benefit: benefit
                )
            }
        }
        .padding(16)
        .background(Constants.Neutral50)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var countdownSection: some View {
        VStack(spacing: 12) {
            Text("Expires in")
                .font(.beVietnamPro(15))
                .tracking(-0.45)
                .foregroundStyle(Constants.ContentB)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = countdown(at: context.date)

                HStack(spacing: 13) {
                    CountdownCell(value: remaining.hours, unit: "hrs")
                    CountdownCell(value: remaining.minutes, unit: "min")
                    CountdownCell(value: remaining.seconds, unit: "sec")
                }
            }

            Label {
                Text("No Payment today")
                    .font(.beVietnamPro(14, weight: .medium))
                    .tracking(-0.42)
            } icon: {
                Image(systemName: "receipt.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.02, green: 0.48, blue: 0.33))
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 16) {
            ZStack {
                SecondaryButton(
                    title: purchaseButtonTitle,
                    variant: .dark
                ) {
                    Task {
                        await purchaseMonthlyPlan()
                    }
                }
                .frame(height: 52)

                if storeManager.isPurchasing {
                    ProgressView()
                        .tint(Constants.White)
                }
            }
            .disabled(
                isLoadingProduct || monthlyProduct == nil
                    || storeManager.isPurchasing
            )
            .opacity(isLoadingProduct || monthlyProduct == nil ? 0.65 : 1)

            // Render only once the product (and its localized price) has loaded,
            // so we never show a hardcoded/possibly-wrong price — App Store review
            // requires the real, storefront-localized price. The purchase CTA is
            // disabled in the same state. Using an interpolated `Text` (a
            // LocalizedStringKey) rather than `String(localized:)` lets this honor
            // the SwiftUI `\.locale` — so it localizes in previews too.
            if let price = monthlyProduct?.displayPrice {
                Text("Plan auto-renews for \(price)/month until canceled.")
                    .font(.beVietnamPro(12))
                    .tracking(-0.36)
                    .foregroundStyle(Constants.ContentM)
                    .multilineTextAlignment(.center)
            }

            if let error = storeManager.error {
                Text(error)
                    .font(.beVietnamPro(12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var purchaseButtonTitle: LocalizedStringKey {
        storeManager.isPurchasing ? " " : "Start 1 month free"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    paywallPromoImage

                    Text(
                        "Stop planning trips across \(Text("Screenshots, Sheets & Videos.").foregroundStyle(Constants.BlueBase))"
                    )
                    .font(.beVietnamPro(19))
                    .tracking(-0.76)
                    .foregroundStyle(Constants.Neutral950)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Text(
                    "Save places from videos, build travel Boards, plan with friends, discover trip ideas, & manage group expenses in one place."
                )
                .font(.beVietnamPro(14))
                .tracking(-0.7)
                .foregroundStyle(Constants.Neutral600)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                legalLink(
                    "Terms of Service",
                    url: "https://oneplan.space/termandconditions"
                )
                legalLink(
                    "Privacy Policy",
                    url: "https://oneplan.space/privacy-policy"
                )
                legalLink(
                    "Terms of Use (EULA)",
                    url:
                        "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
                )
            }
        }
    }

    private var paywallPromoImage: some View {
        ZStack(alignment: .topLeading) {
            Image("oneplanPaywallPromo")
                .resizable()
                .frame(width: 86.8, height: 86.8)
                .offset(x: -6, y: -22.7)
        }
        .frame(width: 70, height: 38, alignment: .topLeading)
        .clipped()
    }

    private func legalLink(_ title: LocalizedStringKey, url: String)
        -> some View
    {
        Link(destination: URL(string: url)!) {
            Text(title)
                .font(.beVietnamPro(14))
                .tracking(-0.7)
                .foregroundStyle(Constants.ContentM)
        }
    }

    private func countdown(at date: Date) -> (
        hours: Int, minutes: Int, seconds: Int
    ) {
        let totalSeconds = max(0, Int(expiryDate.timeIntervalSince(date)))
        return (
            totalSeconds / 3_600,
            (totalSeconds % 3_600) / 60,
            totalSeconds % 60
        )
    }

    @MainActor
    private func loadMonthlyProduct() async {
        defer { isLoadingProduct = false }
        monthlyProduct = try? await Product.products(for: ["pro_monthly"]).first
    }

    @MainActor
    private func purchaseMonthlyPlan() async {
        guard let monthlyProduct else { return }

        do {
            try await storeManager.purchase(monthlyProduct)
            if storeManager.currentTier == .proMonthly {
                close()
            }
        } catch {
            // StoreManager owns the user-facing error state.
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

private struct FreeTrialBenefit: Identifiable {
    let symbol: String
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?

    var id: String { symbol }
}

private struct AnimatedFreeTrialBenefitRow: View {
    let index: Int
    let benefit: FreeTrialBenefit

    @State private var animateSymbol = false
    @State private var animateContent = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if animateSymbol {
                    Image(systemName: benefit.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .symbolVariant(.fill)
                        .foregroundStyle(Constants.ContentB.opacity(0.72))
                        .transition(.blurReplace)
                }
            }
            .frame(width: 20, height: 20)

            Text(benefit.title)
                .font(.beVietnamPro(15))
                .tracking(-0.45)
                .foregroundStyle(Constants.ContentB)
                .lineLimit(1)
                .truncationMode(.tail)
                .visualEffect { [animateContent] content, proxy in
                    content
                        .opacity(animateContent ? 1 : 0)
                        .offset(x: animateContent ? 0 : -proxy.size.width)
                }
                .clipped()

            if let detail = benefit.detail {
                Spacer(minLength: 8)

                Text(detail)
                    .font(.beVietnamPro(15))
                    .tracking(-0.45)
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)
                    .visualEffect { [animateContent] content, proxy in
                        content
                            .opacity(animateContent ? 1 : 0)
                            .offset(
                                x: animateContent ? 0 : proxy.size.width
                            )
                    }
                    .clipped()
            } else {
                Spacer(minLength: 0)
            }
        }
        .task {
            guard !animateSymbol else { return }

            try? await Task.sleep(for: .seconds(0.1))
            try? await Task.sleep(for: .seconds(Double(index) * 0.4))
            withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                animateSymbol = true
            }

            try? await Task.sleep(for: .seconds(Double(index) * 0.1))
            withAnimation(.easeInOut(duration: 0.25)) {
                animateContent = true
            }
        }
    }
}

private struct CountdownCell: View {
    let value: Int
    let unit: LocalizedStringKey

    var body: some View {
        VStack(spacing: 0) {
            Text(value, format: .number)
                .font(.beVietnamPro(32, weight: .medium))
                .tracking(-1.28)
                .foregroundStyle(Constants.Neutral950)

            Text(unit)
                .font(.beVietnamPro(15))
                .tracking(-0.45)
                .foregroundStyle(Constants.Neutral400)
        }
        .frame(width: 78, height: 75)
        .background(Constants.ContentB.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.96, green: 0.96, blue: 0.96), lineWidth: 1)
        }
    }
}

#Preview("English") {
    FreeTrialView()
        .environment(StoreManager())
        .environment(\.locale, Locale(identifier: "en"))
}

#Preview("Vietnamese") {
    FreeTrialView()
        .environment(StoreManager())
        .environment(\.locale, Locale(identifier: "vi"))
}
