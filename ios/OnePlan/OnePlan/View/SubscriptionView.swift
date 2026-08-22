//
//  SubscriptionBottomSheet.swift
//  OnePlan
//
//  Created by ken on 26/3/26.
//

import StoreKit
import SwiftUI
import UIKit

struct PaywallView<Header: View, Links: View, Loader: View>: View {
    var productIDs: [String]
    var points: [PaywallPoint]
    var onClose: (() -> Void)? = nil
    @ViewBuilder var header: Header
    @ViewBuilder var links: Links
    @ViewBuilder var loadingView: Loader
    @Environment(StoreManager.self) private var storeManager
    @State private var products: [Product] = []
    @State private var selectedProductID: String?
    @State private var isLoaded: Bool = false
    @State private var isShowingCompareFeatures: Bool = false
    @State private var isShowingManageSubscriptions: Bool = false
    @State private var isCheckingPromoCode: Bool = false
    @State private var isAwaitingPromoCodeValidation: Bool = false
    @State private var promoCodeAlert: PromoCodeAlert?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    header

                    if isLoaded {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(points.indices, id: \.self) { index in
                                AnimatedPointView(
                                    index: index,
                                    point: points[index],
                                    videoQuotaLabel: videoQuotaLabel(
                                        for: selectedProductID
                                    )
                                )
                            }
                        }
                        .padding(16)
                        .background(Constants.Neutral50)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 20,
                                style: .continuous
                            )
                        )
                        .transition(.identity)
                    }

                    if isLoaded {
                        HorizontalProductPicker(
                            products: products,
                            selectedProductID: $selectedProductID,
                            onCompareFeaturesTap: {
                                isShowingCompareFeatures = true
                            }
                        )

                        /// Subscribe / Buy Button
                        if let selected = products.first(where: {
                            $0.id == selectedProductID
                        }) {
                            /// Auto-renewal notice
                            if selected.type == .autoRenewable,
                                let period = selected.subscription?
                                    .subscriptionPeriod
                            {
                                Text(
                                    "Plan auto-renews for \(selected.displayPrice)/\(period.normalizedDescription) until canceled."
                                )
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .multilineTextAlignment(.center)
                                .foregroundColor(Constants.ContentM)
                                .frame(maxWidth: .infinity, alignment: .top)
                            }

                            if let errorMessage = storeManager.error {
                                Text(errorMessage)
                                    .font(
                                        Font.custom("Be Vietnam Pro", size: 13)
                                    )
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                            if isAwaitingPromoCodeValidation && !storeManager.isPro {
                                Text("Your code was submitted. Verifying Pro access with the App Store...")
                                    .font(Font.custom("Be Vietnam Pro", size: 13))
                                    .foregroundColor(Constants.ContentM)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }

                            let action = primaryAction(for: selected)

                            Button {
                                switch action {
                                case .cancel:
                                    isShowingManageSubscriptions = true
                                case .subscribe, .buy, .upgrade:
                                    Task {
                                        do {
                                            try await storeManager.purchase(
                                                selected
                                            )
                                            // Close only once the selected
                                            // plan is actually the active
                                            // tier. `isPro` is already true
                                            // for an upgrader, and a
                                            // cancelled / pending purchase
                                            // does not throw, so gating on
                                            // `isPro` would dismiss wrongly.
                                            if storeManager.currentTier
                                                .rawValue == selected.id
                                            {
                                                onClose?()
                                            }
                                        } catch {
                                            // Error is already set in storeManager.error
                                        }
                                    }
                                }
                            } label: {
                                Text(action.label)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.primary, in: .capsule)
                            }
                            .disabled(storeManager.isPurchasing)
                            .padding(.horizontal, 8)
                            .accessibilityHint(
                                action == .cancel
                                    ? String(localized: "Opens the system subscription management screen")
                                    : ""
                            )

                            Button {
                                UIImpactFeedbackGenerator(style: .light)
                                    .impactOccurred()
                                Task {
                                    await presentOfferCodeRedemption()
                                }
                            } label: {
                                Text("Have a promo code?")
                                    .font(Font.custom("Be Vietnam Pro", size: 15))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(Constants.Neutral950)
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }
                            .buttonStyle(.plain)
                            .disabled(isCheckingPromoCode)
                            .opacity(isCheckingPromoCode ? 0.6 : 1)
                            .padding(.top, 8)

                        }
                    }

                    links
                        .buttonStyle(.plain)
                        .padding(.vertical, 5)
                }
                .padding(.horizontal, 15)
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .animation(.easeInOut(duration: 0.35)) { content in
                content.opacity(isLoaded ? 1 : 0)
            }
            .overlay {
                ZStack {
                    if !isLoaded {
                        loadingView
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: isLoaded)
            }
            .background {
                ZStack(alignment: .top) {
                    Color(.white)
                        .ignoresSafeArea()

                    topBlurBackground
                        .ignoresSafeArea(.all, edges: .top)
                }
            }
            .onAppear {
                AnalyticsClient.shared.track(.SUBSCRIPTION_VIEWED)
            }
            .task {
                do {
                    let fetched = try await Product.products(for: productIDs)
                    #if DEBUG
                        for product in fetched {
                            print("[StoreKit Debug] Product: \(product.id)")
                            if let sub = product.subscription {
                                print(
                                    "[StoreKit Debug]   Period: \(sub.subscriptionPeriod.value) \(sub.subscriptionPeriod.unit)"
                                )
                            }
                        }
                    #endif
                    /// Sort to match the order of productIDs
                    products = productIDs.compactMap { id in
                        fetched.first(where: { $0.id == id })
                    }
                    /// Default to the longest-period subscription ("Best value")
                    let subscriptions = products.filter {
                        $0.subscription != nil
                    }
                    let bestValueID = subscriptions.max(by: {
                        Self.periodWeight($0) < Self.periodWeight($1)
                    })?.id
                    selectedProductID = bestValueID ?? products.first?.id
                    isLoaded = true
                } catch {
                    isLoaded = true
                }
            }
            .navigationDestination(isPresented: $isShowingCompareFeatures) {
                CompareFeatureView()
            }
            .manageSubscriptionsSheet(
                isPresented: $isShowingManageSubscriptions
            )
            .alert(item: $promoCodeAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onChange(of: isShowingManageSubscriptions) { _, shown in
                if !shown {
                    Task {
                        await storeManager.refreshSubscriptionStatus(
                            silent: true
                        )
                    }
                }
            }
            .onChange(of: storeManager.isPro) { _, isPro in
                if isAwaitingPromoCodeValidation && isPro {
                    isAwaitingPromoCodeValidation = false
                    onClose?()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        AnalyticsClient.shared.track(.RESTORE_PURCHASE_CLICKED)
                        Task {
                            do {
                                try await storeManager.restorePurchases()
                                if storeManager.isPro {
                                    onClose?()
                                }
                            } catch {
                                // Error is already set in storeManager.error
                            }
                        }
                    } label: {
                        Text("Restore")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Constants.ContentB)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .glassEffectCompat()
                            .clipShape(Capsule())
                    }
                    .disabled(storeManager.isPurchasing)
                }
                .sharedBackgroundHiddenCompat()

                if let onClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        ToolbarIconButton(systemName: "xmark", action: onClose)
                    }
                    .sharedBackgroundHiddenCompat()
                }
            }
        }
    }

    /// Ranks subscription periods by approximate length so the "Best value"
    /// (longest period) can be preselected.
    private static func periodWeight(_ product: Product) -> Int {
        guard let period = product.subscription?.subscriptionPeriod else {
            return -1
        }
        let unitDays: Int
        switch period.unit {
        case .day: unitDays = 1
        case .week: unitDays = 7
        case .month: unitDays = 30
        case .year: unitDays = 365
        @unknown default: unitDays = 0
        }
        return unitDays * period.value
    }

    private enum PrimaryAction: Equatable {
        case subscribe, buy, cancel, upgrade

        var label: LocalizedStringKey {
            switch self {
            case .subscribe: "Subscribe"
            case .buy: "Buy"
            case .cancel: "Cancel Subscription"
            case .upgrade: "Change Plan"
            }
        }
    }

    /// Resolves the primary CTA. When the user is Pro the button manages the
    /// subscription: `.cancel` (opens the system Manage Subscriptions sheet)
    /// when the selected plan is the active one, otherwise `.upgrade` — a
    /// normal in-group purchase that StoreKit prorates. `currentTier` is
    /// `.free` for non-Pro / unmapped, so the comparison degrades to a safe
    /// `.upgrade`.
    private func primaryAction(for selected: Product) -> PrimaryAction {
        guard storeManager.isPro else {
            return selected.type == .autoRenewable ? .subscribe : .buy
        }
        let currentID =
            storeManager.currentTier == .free
            ? nil : storeManager.currentTier.rawValue
        return selected.id == currentID ? .cancel : .upgrade
    }

    /// Scan credits granted in full per billing cycle (upfront on purchase
    /// and again on each renewal). Mirrors the server defaults
    /// SCAN_GRANT_PRO_WEEKLY/_MONTHLY/_YEARLY = 3 / 20 / 300.
    // Returns a LocalizedStringKey (not String(localized:)) so the label honors
    // the SwiftUI `\.locale` — including in previews.
    private func videoQuotaLabel(for selectedProductID: String?) -> LocalizedStringKey {
        guard let selectedProductID,
            let product = products.first(where: { $0.id == selectedProductID })
        else {
            return "300 scans / year"
        }

        let normalizedPlanText = "\(product.id) \(product.displayName)"
            .lowercased()
        if normalizedPlanText.contains("week") {
            return "3 scans / week"
        }
        if normalizedPlanText.contains("month") {
            return "20 scans / month"
        }
        return "300 scans / year"
    }

    private func presentOfferCodeRedemption() async {
        guard let scene = activeWindowScene else {
            promoCodeAlert = PromoCodeAlert(
                title: String(localized: "Promo Code"),
                message: String(localized: "We couldn't open the promo code sheet. Please try again.")
            )
            return
        }

        isCheckingPromoCode = true
        defer { isCheckingPromoCode = false }

        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: scene)
            isAwaitingPromoCodeValidation = true
            try? await storeManager.reconcileAfterOfferCodeRedemption()
            if storeManager.isPro {
                isAwaitingPromoCodeValidation = false
                onClose?()
            }
        } catch {
            promoCodeAlert = PromoCodeAlert(
                title: String(localized: "Promo Code"),
                message: String(localized: "We couldn't open the App Store promo code sheet. Please try again.")
            )
        }
    }

    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
    }
}

private struct PromoCodeAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private var topBlurBackground: some View {
    Circle()
        .fill(
            Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1))
        )
        .frame(width: 435, height: 455)
        .blur(radius: 60)
        .offset(y: -310)
        .allowsHitTesting(false)
}

// MARK: - Horizontal Product Picker

private struct HorizontalProductPicker: View {
    var products: [Product]
    @Binding var selectedProductID: String?
    var onCompareFeaturesTap: () -> Void
    @State private var scrollPositionID: String?
    @State private var isSelectionHapticReady = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let cardWidth: CGFloat = 239
    private static let horizontalPadding: CGFloat = 10
    private static let finalCardPeek: CGFloat = 72

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(products) { product in
                        let isSelected = selectedProductID == product.id

                        Button {
                            withAnimation(
                                reduceMotion
                                    ? .none
                                    : .snappy(duration: 0.22, extraBounce: 0)
                            ) {
                                selectedProductID = product.id
                            }
                        } label: {
                            VStack(spacing: 0) {
                                VStack(spacing: 0) {
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 4)
                                        {
                                            Text(displayName(for: product))
                                                .font(
                                                    Font.beVietnamPro(16, weight: .semibold)
                                                )
                                                .tracking(-0.48)
                                                .foregroundStyle(
                                                    Constants.ContentB
                                                )
                                                .lineLimit(1)
                                            Text(priceLabel(for: product))
                                                .font(
                                                    Font.custom(
                                                        "Be Vietnam Pro",
                                                        size: 14
                                                    )
                                                )
                                                .tracking(-0.42)
                                                .foregroundStyle(
                                                    Constants.ContentB
                                                )
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 0)

                                        ZStack {
                                            if isSelected {
                                                Image(
                                                    systemName:
                                                        "checkmark.circle.fill"
                                                )
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 20, height: 20)
                                                .foregroundStyle(
                                                    Constants.ContentB
                                                )
                                                .transition(
                                                    .scale(scale: 0.9)
                                                        .combined(
                                                            with: .opacity
                                                        )
                                                )
                                            }
                                        }
                                        .frame(width: 20, height: 20)
                                    }
                                    .padding(.top, 16)
                                    .padding(.horizontal, 15)

                                    Spacer(minLength: 0)
                                }
                                .frame(height: 87)

                                Rectangle()
                                    .fill(Constants.Neutral200)
                                    .frame(height: 1)

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dailyPriceLabel(for: product))
                                            .font(
                                                Font.custom(
                                                    "Be Vietnam Pro",
                                                    size: 14
                                                )
                                            )
                                            .tracking(-0.42)
                                            .foregroundStyle(Constants.ContentM)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 15)
                                .padding(.top, 10)
                                .padding(.bottom, 14)
                            }
                            .frame(width: Self.cardWidth, height: 131)
                            .background(Constants.Neutral50)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                            )
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                                .stroke(
                                    isSelected
                                        ? Constants.ContentB
                                        : Color.clear,
                                    lineWidth: 2
                                )
                            )
                            .scaleEffect(isSelected ? 1.04 : 1)
                            .zIndex(isSelected ? 1 : 0)
                            .animation(
                                reduceMotion
                                    ? .none
                                    : .snappy(duration: 0.2, extraBounce: 0),
                                value: isSelected
                            )
                        }
                        .buttonStyle(.plain)
                        .id(product.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 5)
                .padding(.leading, Self.horizontalPadding)
                .padding(.trailing, trailingPadding(for: proxy.size.width))
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollPositionID)
            .scrollIndicators(.hidden)
        }
        .frame(height: 141)
        .onAppear {
            let initialID = selectedProductID ?? products.first?.id
            if selectedProductID == nil {
                selectedProductID = initialID
            }
            scrollPositionID = initialID
            DispatchQueue.main.async {
                isSelectionHapticReady = true
            }
        }
        .onChange(of: products.map(\.id)) { _, _ in
            let fallbackID = products.first?.id
            if selectedProductID == nil {
                selectedProductID = fallbackID
            }
            if let selectedProductID,
                products.contains(where: { $0.id == selectedProductID })
            {
                scrollPositionID = selectedProductID
            } else {
                scrollPositionID = fallbackID
                selectedProductID = fallbackID
            }
        }
        .onChange(of: scrollPositionID) { _, newValue in
            guard let newValue, selectedProductID != newValue else { return }
            triggerSelectionHaptic()
            withAnimation(
                reduceMotion ? .none : .snappy(duration: 0.2, extraBounce: 0)
            ) {
                selectedProductID = newValue
            }
        }
        .onChange(of: selectedProductID) { _, newValue in
            guard let newValue, scrollPositionID != newValue else { return }
            triggerSelectionHaptic()
            withAnimation(
                reduceMotion ? .none : .snappy(duration: 0.2, extraBounce: 0)
            ) {
                scrollPositionID = newValue
            }
        }

        if products.count > 1 {
            HStack(spacing: 6) {
                ForEach(products) { product in
                    Circle()
                        .fill(
                            selectedProductID == product.id
                                ? Constants.ContentB
                                : Constants.Neutral200
                        )
                        .frame(width: 7, height: 7)
                }
            }
            .animation(
                reduceMotion ? .none : .snappy(duration: 0.2, extraBounce: 0),
                value: selectedProductID
            )
            .padding(.top, 10)
        }

        Button {
            onCompareFeaturesTap()
        } label: {
            Text("Compare features")
                .font(Font.custom("Be Vietnam Pro", size: 15))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentB)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 20)
    }

    private func trailingPadding(for width: CGFloat) -> CGFloat {
        max(
            Self.horizontalPadding,
            width - Self.cardWidth - Self.horizontalPadding - Self.finalCardPeek
        )
    }

    private func triggerSelectionHaptic() {
        guard isSelectionHapticReady else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func displayName(for product: Product) -> String {
        let trimmed = product.displayName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.displayName
        }
        switch period.unit {
        case .day where period.value == 7: return String(localized: "Weekly")
        case .day where period.value == 14: return String(localized: "Bi-Weekly")
        case .day: return String(localized: "Daily")
        case .week:
            return period.value == 1 ? String(localized: "Weekly") : String(localized: "\(period.value) Weeks")
        case .month:
            return period.value == 1 ? String(localized: "Monthly") : String(localized: "\(period.value) Months")
        case .year:
            return period.value == 1 ? String(localized: "Yearly") : String(localized: "\(period.value) Years")
        @unknown default: return product.displayName
        }
    }

    private func priceLabel(for product: Product) -> String {
        if let period = product.subscription?.subscriptionPeriod {
            return "\(product.displayPrice)/\(period.normalizedDescription)"
        }
        return product.displayPrice
    }

    private func dailyPriceLabel(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod,
            let days = period.approximateDayCount,
            days > 0
        else {
            return product.description
        }

        let dailyPrice = product.price / Decimal(days)
        return String(localized: "~\(dailyPrice.formatted(product.priceFormatStyle))/day", comment: "%@ = daily price")
    }
}

// MARK: - Animated Point View

private struct AnimatedPointView: View {
    var index: Int
    var point: PaywallPoint
    var videoQuotaLabel: LocalizedStringKey
    @State private var animateSymbol: Bool = false
    @State private var animateContent: Bool = false
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if animateSymbol {
                    Image(systemName: point.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .symbolVariant(.fill)
                        .foregroundStyle(point.symbolTint)
                        .transition(.blurReplace)
                }
            }
            .frame(width: 20, height: 20)

            Text(point.content)
                .font(Font.custom("Be Vietnam Pro", size: 15))
                .tracking(-0.45)
                .foregroundStyle(Constants.ContentB)
                .lineLimit(1)
                .truncationMode(.tail)
                .visualEffect({ [animateContent] content, proxy in
                    content
                        .opacity(animateContent ? 1 : 0)
                        .offset(x: animateContent ? 0 : -proxy.size.width)
                })
                .clipped()

            if point.showsVideoQuota {
                Spacer(minLength: 8)

                Text(videoQuotaLabel)
                    .font(Font.custom("Be Vietnam Pro", size: 15))
                    .tracking(-0.45)
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)
                    .visualEffect({ [animateContent] content, proxy in
                        content
                            .opacity(animateContent ? 1 : 0)
                            .offset(x: animateContent ? 0 : proxy.size.width)
                    })
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

// MARK: - Subscription Period Helper

extension Product.SubscriptionPeriod.Unit {
    var localizedDescription: String {
        switch self {
        case .day: String(localized: "day", comment: "Subscription period unit")
        case .week: String(localized: "week", comment: "Subscription period unit")
        case .month: String(localized: "month", comment: "Subscription period unit")
        case .year: String(localized: "year", comment: "Subscription period unit")
        @unknown default: ""
        }
    }
}

extension Product.SubscriptionPeriod {
    /// Normalizes the period for display, handling Apple's bug where
    /// Sandbox/App Store returns weekly subscriptions as "7 days" instead of "1 week"
    var normalizedDescription: String {
        // Apple bug: weekly subscriptions return as 7 days in Sandbox/production
        if unit == .day && value == 7 {
            return String(localized: "week", comment: "Subscription period unit")
        }
        // 14 days → 2 weeks (for 2-week offers)
        if unit == .day && value == 14 {
            return String(localized: "2 weeks", comment: "Subscription period")
        }
        return unit.localizedDescription
    }

    var approximateDayCount: Int? {
        switch unit {
        case .day: value
        case .week: value * 7
        case .month: value * 30
        case .year: value * 365
        @unknown default: nil
        }
    }
}

/// Paywall Point Model
struct PaywallPoint: Identifiable {
    var id: String = UUID().uuidString
    var symbol: String
    var symbolTint: Color = .black
    var content: LocalizedStringKey
    var showsVideoQuota: Bool = false
}

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    var onClose: (() -> Void)?

    var body: some View {
        PaywallView(
            productIDs: ["pro_yearly", "pro_monthly", "pro_weekly"],
            points: [
                .init(
                    symbol: "icloud.and.arrow.up",
                    content: "Upload plans on market"
                ),
                .init(
                    symbol: "map",
                    content: "Unlimited planning trips"
                ),
                .init(
                    symbol: "receipt",
                    content: "Split bill by AI"
                ),
                .init(
                    symbol: "play.rectangle.on.rectangle",
                    content: "Extract pins by video",
                    showsVideoQuota: true
                ),
                .init(symbol: "signpost.right", content: "Trip insights"),
                //                .init(symbol: "signpost.right", content: "Live activities"),
            ],
            onClose: {
                if let onClose {
                    onClose()
                } else {
                    dismiss()
                }
            }
        ) {
            VStack(spacing: 15) {
                HStack(spacing: 6) {
                    Text("One Plan")
                        .font(
                            Font.beVietnamPro(24, weight: .semibold)
                        )
                        .tracking(-0.72)
                        .foregroundStyle(Constants.White)

                    Text("Pro")
                        .font(Font.custom("Be Vietnam Pro   ", size: 13))
                        .tracking(-0.52)
                        .foregroundStyle(Constants.BlueBase)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Constants.Surface)
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 6,
                                style: .continuous
                            )
                            .stroke(Constants.BlueBase, lineWidth: 1)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 6,
                                style: .continuous
                            )
                        )
                }

                OnePlanProLogoBadge(size: 68, showsShadow: false)
            }
        } links: {
            PaywallLegalFooter()
                .padding(.top, 60)
        } loadingView: {
            ProgressView()
        }
    }
}

private struct PaywallLegalFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            promoMessage
            legalLinks
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var promoMessage: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                paywallPromoImage

                // One localizable sentence; the styled run is an inline %@.
                Text("Stop planning trips across \(Text("Screenshots, Sheets & Videos.").foregroundStyle(Constants.BlueBase))")
                    .foregroundStyle(Constants.Neutral950)
                    .font(Font.custom("Be Vietnam Pro", size: 19))
                    .tracking(-0.76)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(
                "Save places from videos, build travel Boards, plan with friends, discover trip ideas, & manage group expenses in one place."
            )
            .font(Font.custom("Be Vietnam Pro", size: 14))
            .tracking(-0.7)
            .foregroundStyle(Constants.Neutral600)
            .lineSpacing(0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var legalLinks: some View {
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

    private func legalLink(_ title: LocalizedStringKey, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .tracking(-0.7)
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)
        }
    }
}

#Preview("English") {
    SubscriptionView()
        .environment(StoreManager())
        .environment(\.locale, Locale(identifier: "en"))
}

#Preview("Vietnamese") {
    SubscriptionView()
        .environment(StoreManager())
        .environment(\.locale, Locale(identifier: "vi"))
}
