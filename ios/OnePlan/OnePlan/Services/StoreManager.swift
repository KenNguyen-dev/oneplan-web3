//
//  StoreManager.swift
//  OnePlan
//

import StoreKit
import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

typealias ValidateTransactionDto = Components.Schemas.ValidateTransactionDto
typealias SubscriptionStatusDto = Components.Schemas.SubscriptionStatusDto
typealias AppAccountTokenDto = Components.Schemas.AppAccountTokenDto

@MainActor
@Observable
final class StoreManager {
    // MARK: - Published State
    var isPro: Bool = false
    var subscriptionStatus: SubscriptionStatus = .none
    var currentTier: SubscriptionTier = .free
    var isPurchasing: Bool = false
    var error: String?
    /// True when at least one unfinished StoreKit transaction failed server
    /// validation during the cold-start sweep. UI can use this to surface a
    /// "We couldn't verify your last purchase — tap Restore" CTA so users
    /// aren't stuck in a silent retry loop.
    var hasPendingPurchaseRetry: Bool = false

    // MARK: - Private
    // Note: nonisolated(unsafe) allows deinit to cancel the task
    nonisolated(unsafe) private var updateListenerTask: Task<Void, Never>?
    private var client: Client { APIClient.shared }

    enum SubscriptionStatus: String {
        case none
        case active
        case gracePeriod
        case billingRetry
        case expired
        case revoked
    }

    // Matches server-side quota tier identifiers. Used by paywall UX and to
    // pre-render the right messaging in QuotaExceededSheet.
    enum SubscriptionTier: String {
        case free
        case proWeekly = "pro_weekly"
        case proMonthly = "pro_monthly"
        case proYearly = "pro_yearly"
        case payOnce = "pay_once"
    }

    private static let proProductIDs: Set<String> = [
        "pro_weekly", "pro_monthly", "pro_yearly", "pay_once",
    ]

    // Consumable scan-credit packs. These must exactly match App Store Connect.
    // Deliberately NOT in proProductIDs — buying a pack must never flip
    // isPro/currentTier.
    static let scanPackProductIDs: Set<String> = [
        "oneplan.video_scan_1",
        "oneplan.video_scan_5",
        "oneplan.video_scan_15",
        "oneplan.video_scan_30",
    ]

    // Loaded StoreKit products for the buy-credits sheet (localized prices).
    private(set) var scanPackProducts: [Product] = []

    init() {
        // Entitlement state is account-scoped and server-owned. StoreKit is
        // used to produce JWS transactions for purchase / restore validation,
        // but it must not grant Pro to whichever OnePlan account is currently
        // signed in on this device.
        updateListenerTask = listenForTransactions()

        Task {
            await processUnfinishedTransactions()
            await loadScanPackProducts()
        }
    }

    // Fetches the consumable scan-credit pack products so the buy sheet can
    // show StoreKit-localized prices. Best-effort; the sheet handles empty.
    func loadScanPackProducts() async {
        guard let products = try? await Product.products(
            for: Self.scanPackProductIDs
        ) else { return }
        // Stable order: ascending pack size.
        scanPackProducts = products.sorted {
            (Self.packCredits(for: $0.id) ?? 0)
                < (Self.packCredits(for: $1.id) ?? 0)
        }
    }

    // Credit count encoded in the product id, e.g.
    // "oneplan.video_scan_15" -> 15. Also accepts the old local StoreKit IDs.
    // Pure string parsing — nonisolated so the buy-sheet presenter can map
    // products without hopping to the main actor.
    nonisolated static func packCredits(for productID: String) -> Int? {
        if productID.hasPrefix("oneplan.video_scan_") {
            return Int(productID.dropFirst("oneplan.video_scan_".count))
        }
        if productID.hasPrefix("scan_pack_") {
            return Int(productID.dropFirst("scan_pack_".count))
        }
        return nil
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Transaction Listener
    // MUST be persistent - runs for app lifetime
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                await self.handleTransaction(result)
            }
        }
    }

    // MARK: - Handle incoming transaction
    private func handleTransaction(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }

        // Check for refund/revocation. Only Pro products affect subscription
        // state — a refunded consumable scan pack must NOT flip isPro/tier.
        if transaction.revocationDate != nil {
            if Self.proProductIDs.contains(transaction.productID) {
                isPro = false
                subscriptionStatus = .revoked
            } else {
                // Refunded scan pack: balance is server-owned (no clawback in
                // v1); just refresh the badge.
                NotificationCenter.default.post(
                    name: .scanCreditBalanceChanged, object: nil
                )
            }
            await transaction.finish()
            return
        }

        // Validate with server
        do {
            try await validateWithServer(jws: result.jwsRepresentation)
            await transaction.finish()
            if Self.scanPackProductIDs.contains(transaction.productID) {
                // Consumables never appear in currentEntitlements, so an
                // entitlement rescan is pointless — just refresh the balance.
                NotificationCenter.default.post(
                    name: .scanCreditBalanceChanged, object: nil
                )
            }
        } catch {
            // Server validation failed - don't finish transaction
            self.error = String(localized: "Failed to validate purchase")
        }
    }

    // MARK: - Process Unfinished Transactions
    // Handle interrupted purchases (app killed mid-purchase, Ask to Buy approval, etc.).
    // Tracks whether any transaction failed validation so the UI can prompt
    // a manual Restore Purchases retry instead of silently looping each cold
    // start.
    private func processUnfinishedTransactions() async {
        var validationFailureSeen = false
        for await result in Transaction.unfinished {
            let didFinish = await handleTransactionTrackingFailure(result)
            if !didFinish { validationFailureSeen = true }
        }
        hasPendingPurchaseRetry = validationFailureSeen
    }

    /// Returns true if the transaction was finished (either by revocation
    /// cleanup or a successful server validation), false if it was left
    /// unfinished because server validation failed.
    private func handleTransactionTrackingFailure(
        _ result: VerificationResult<Transaction>
    ) async -> Bool {
        guard case .verified(let transaction) = result else { return false }

        if transaction.revocationDate != nil {
            if Self.proProductIDs.contains(transaction.productID) {
                isPro = false
                subscriptionStatus = .revoked
            } else {
                NotificationCenter.default.post(
                    name: .scanCreditBalanceChanged, object: nil
                )
            }
            await transaction.finish()
            return true
        }

        do {
            try await validateWithServer(jws: result.jwsRepresentation)
            await transaction.finish()
            if Self.scanPackProductIDs.contains(transaction.productID) {
                NotificationCenter.default.post(
                    name: .scanCreditBalanceChanged, object: nil
                )
            }
            return true
        } catch {
            self.error = String(localized: "Failed to validate purchase")
            return false
        }
    }

    // MARK: - Account-scoped subscription state
    func resetEntitlementState() {
        isPro = false
        subscriptionStatus = .none
        currentTier = .free
        error = nil
    }

    func refreshSubscriptionStatus(silent: Bool = false) async {
        do {
            let response = try await client.getSubscriptionStatus(.init())
            let status = try response.ok.body.json
            applyServerStatus(status)
        } catch {
            // Silent best-effort refresh (foreground): leave last known-good
            // entitlement state intact and surface nothing. A genuine refund
            // still applies because applyServerStatus() runs on the SUCCESS
            // path above, independent of `silent`.
            if silent { return }
            resetEntitlementState()
            self.error = String(localized: "Failed to load subscription status")
        }
    }

    // MARK: - Free Trial Eligibility
    // Whether to surface the 1-month free-trial promo (FreeTrialView) to this
    // user. False for anyone already Pro; otherwise defers to StoreKit's
    // per-account introductory-offer eligibility for pro_monthly. The intro
    // offer itself is applied automatically by StoreKit on purchase() when
    // eligible — this only gates the UI so we never promise "free" to a user
    // who would be charged immediately.
    func isEligibleForFreeTrial() async -> Bool {
        guard !isPro else { return false }
        guard
            let product = try? await Product.products(
                for: [SubscriptionTier.proMonthly.rawValue]
            ).first,
            let subscription = product.subscription
        else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    // MARK: - Purchase
    // CRITICAL: Call transaction.finish() ONLY after server confirms
    func purchase(_ product: Product) async throws {
        isPurchasing = true
        error = nil

        defer { isPurchasing = false }

        let result: Product.PurchaseResult
        do {
            if product.type == .autoRenewable {
                let appAccountToken = try await fetchAppAccountToken()
                result = try await product.purchase(
                    options: [.appAccountToken(appAccountToken)]
                )
            } else {
                result = try await product.purchase()
            }
        } catch {
            self.error = String(localized: "Purchase failed: \(error.localizedDescription)")
            throw error
        }

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                self.error = String(localized: "Purchase verification failed")
                throw PurchaseError.verificationFailed
            }

            // Send JWS to server FIRST. If validation fails, do NOT finish the
            // transaction and do NOT mutate entitlement state — Apple will
            // surface the transaction again via Transaction.unfinished on the
            // next launch so the user can retry.
            do {
                try await validateWithServer(jws: verification.jwsRepresentation)
            } catch {
                self.error = String(localized: "Server validation failed. Please try again.")
                throw error
            }
            await transaction.finish()

        case .pending:
            // Ask to Buy - do NOT finish
            // Transaction will arrive via Transaction.updates when approved
            self.error = String(localized: "Purchase pending approval")

        case .userCancelled:
            // User cancelled - not an error
            break

        @unknown default:
            break
        }
    }

    // MARK: - Purchase scan-credit pack (consumable)
    // Same verify → server-validate → finish flow as purchase(), but for a
    // consumable: the server SKU-guards /subscription/validate and returns the
    // user's REAL (unchanged) SubscriptionStatusDto for credit products, so
    // reusing validateWithServer/applyServerStatus is a no-op for tier state.
    // Skips updateEntitlements() (consumables never appear in
    // currentEntitlements) and posts .scanCreditBalanceChanged so the badge
    // refreshes after the presenting sheet has already dismissed.
    func purchaseScanCredits(_ product: Product) async throws {
        isPurchasing = true
        error = nil
        defer { isPurchasing = false }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            self.error = String(localized: "Purchase failed: \(error.localizedDescription)")
            throw error
        }

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                self.error = String(localized: "Purchase verification failed")
                throw PurchaseError.verificationFailed
            }
            do {
                try await validateWithServer(jws: verification.jwsRepresentation)
            } catch {
                self.error = String(localized: "Server validation failed. Please try again.")
                throw error
            }
            await transaction.finish()
            NotificationCenter.default.post(
                name: .scanCreditBalanceChanged, object: nil
            )

        case .pending:
            // Ask to Buy — Transaction.updates handles it on approval.
            self.error = String(localized: "Purchase pending approval")

        case .userCancelled:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Restore Purchases
    func restorePurchases() async throws {
        isPurchasing = true
        error = nil

        defer { isPurchasing = false }

        try await AppStore.sync()

        // Resync local cache with StoreKit, then re-validate the most recent
        // pro entitlement against the server so refunds/revocations issued
        // on Apple's side after the JWS was first cached take effect. Without
        // this, `Transaction.currentEntitlements` can keep reporting a
        // refunded transaction and grant Pro indefinitely.
        do {
            _ = try await validateLatestCurrentProEntitlement()
            try await synchronizeLinkedSubscription()
        } catch {
            self.error = String(localized: "Could not verify your purchase with the server.")
            throw error
        }

        // A successful restore clears the "we couldn't verify your last
        // purchase" banner. If validation above threw, this line is skipped
        // and the flag stays set so the UI keeps surfacing the retry CTA.
        hasPendingPurchaseRetry = false
    }

    /// Offer-code redemptions complete asynchronously through
    /// `Transaction.updates`. This bounded attempt handles the common case
    /// where StoreKit already exposes the new entitlement, then asks the
    /// server to refresh any previously linked subscription.
    func reconcileAfterOfferCodeRedemption() async throws {
        try? await Task.sleep(for: .milliseconds(500))
        _ = try await validateLatestCurrentProEntitlement()
        try await synchronizeLinkedSubscription()
    }

    // MARK: - Server Validation
    private func fetchAppAccountToken() async throws -> UUID {
        let response = try await client.getSubscriptionAppAccountToken(.init())
        let token: AppAccountTokenDto
        switch response {
        case .ok(let okResponse):
            token = try okResponse.body.json
        case .undocumented:
            throw PurchaseError.serverValidationFailed
        }
        guard let uuid = UUID(uuidString: token.appAccountToken) else {
            throw PurchaseError.serverValidationFailed
        }
        return uuid
    }

    private func validateLatestCurrentProEntitlement() async throws -> Bool {
        var latestProJWS: String?
        var latestPurchaseDate: Date = .distantPast
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.revocationDate == nil,
               Self.proProductIDs.contains(transaction.productID),
               transaction.purchaseDate > latestPurchaseDate {
                latestPurchaseDate = transaction.purchaseDate
                latestProJWS = result.jwsRepresentation
            }
        }
        guard let latestProJWS else { return false }
        try await validateWithServer(jws: latestProJWS)
        return true
    }

    private func synchronizeLinkedSubscription() async throws {
        let response = try await client.syncSubscriptionStatus(.init())
        switch response {
        case .ok(let okResponse):
            applyServerStatus(try okResponse.body.json)
        case .badRequest, .serviceUnavailable, .undocumented:
            throw PurchaseError.serverValidationFailed
        }
    }

    private func validateWithServer(jws: String) async throws {
        let response = try await client.validateSubscriptionTransaction(
            .init(body: .json(.init(jws: jws)))
        )

        switch response {
        case .ok(let okResponse):
            let status = try okResponse.body.json
            applyServerStatus(status)

        case .created(let createdResponse):
            let status = try createdResponse.body.json
            applyServerStatus(status)

        case .badRequest, .undocumented:
            throw PurchaseError.serverValidationFailed
        }
    }

    // MARK: - Apply server status to local state
    private func applyServerStatus(_ status: SubscriptionStatusDto) {
        let serverStatus = status.status
        let tier = status.productId.flatMap { SubscriptionTier(rawValue: $0) }

        switch serverStatus {
        case .ACTIVE, .GRACE_PERIOD:
            subscriptionStatus = .active
            isPro = true
            currentTier = tier ?? .free
        case .BILLING_RETRY:
            subscriptionStatus = .billingRetry
            isPro = false
            currentTier = .free
        case .EXPIRED:
            subscriptionStatus = .expired
            isPro = false
            currentTier = .free
        case .REVOKED:
            subscriptionStatus = .revoked
            isPro = false
            currentTier = .free
        case .NONE:
            subscriptionStatus = .none
            isPro = false
            currentTier = .free
        }
    }

    /// Removes any legacy cached entitlement values written by previous app
    /// versions. Kept for migration cleanup; new versions don't write these.
    static func clearEntitlementCache() {
        UserDefaults.standard.removeObject(forKey: "isPro")
        UserDefaults.standard.removeObject(forKey: "subscriptionStatus")
    }

    // MARK: - Errors
    enum PurchaseError: LocalizedError {
        case verificationFailed
        case serverValidationFailed

        var errorDescription: String? {
            switch self {
            case .verificationFailed: return "Purchase verification failed"
            case .serverValidationFailed: return "Server validation failed"
            }
        }
    }
}
