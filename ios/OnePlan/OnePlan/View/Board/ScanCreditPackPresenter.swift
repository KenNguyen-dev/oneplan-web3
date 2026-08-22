//
//  ScanCreditPackPresenter.swift
//  OnePlan
//
//  Maps StoreKit scan-credit pack products into the existing designed
//  `VideoExtractionQuotaPackage` model so `BuyVideoExtractionQuotaBottomSheet`
//  can be reused as-is (data only — no layout changes). Prices come from
//  StoreKit's localized `displayPrice` (App Store requirement).
//

import Foundation
import StoreKit

enum ScanCreditPackPresenter {
    static func packages(
        from products: [Product]
    ) -> [VideoExtractionQuotaPackage] {
        // Highest per-credit price across packs → baseline for "Save x%".
        let maxPerUnit: Double? = products
            .compactMap { product -> Double? in
                guard
                    let credits = StoreManager.packCredits(for: product.id),
                    credits > 0
                else { return nil }
                return NSDecimalNumber(decimal: product.price).doubleValue
                    / Double(credits)
            }
            .max()

        return products.compactMap { product in
            guard
                let credits = StoreManager.packCredits(for: product.id)
            else { return nil }

            var badge: String?
            if let maxPerUnit, maxPerUnit > 0, credits > 1 {
                let perUnit =
                    NSDecimalNumber(decimal: product.price).doubleValue
                    / Double(credits)
                let pct = Int(((1 - perUnit / maxPerUnit) * 100).rounded())
                if pct >= 1 { badge = "Save \(pct)%" }
            }

            let footnote: String?
            switch credits {
            case 1: footnote = "Most popular"
            case let c where c == products.compactMap({
                StoreManager.packCredits(for: $0.id)
            }).max(): footnote = "Best value"
            default: footnote = nil
            }

            let unit = credits == 1 ? "1 video scan" : "\(credits) video scans"
            return VideoExtractionQuotaPackage(
                id: product.id,
                title: unit,
                priceDetail: product.displayPrice,
                badge: badge,
                footnote: footnote,
                ctaTitle: "Get \(unit) · \(product.displayPrice)"
            )
        }
    }
}
