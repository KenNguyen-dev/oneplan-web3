//
//  PinExtractionLauncher.swift
//  OnePlan
//
//  Created by ken on 3/7/26.
//

import StoreKit
import SwiftUI

// Programmatic route into ProcessPinView. Shared by BoardView and HomeView
// through PinExtractionLauncher — each view owns its OWN launcher instance
// (only one tab is mounted at a time, and a per-view instance means an
// unconsumed pending route can't re-push after a tab switch).
enum PendingExtraction: Identifiable, Hashable {
    case fresh(url: String)
    case resume(sessionId: String)

    var id: String {
        switch self {
        case .fresh(let url): return "url:" + url
        case .resume(let sessionId): return "session:" + sessionId
        }
    }
}

// Extracted from BoardView so HomeView can offer the same paste-link entry
// (pin-extraction banner + "Import via link" quick-access card) without
// duplicating the credit gate / clipboard / analytics logic.
//
// Deliberately NOT included: Share-Extension / push deep-link consumption
// (`DeepLinkRouter.consumePendingPinExtraction*`) — BoardView remains the
// sole owner of those (see MainView's deep-link comments); bundling them
// here would let a Home-mounted launcher race BoardView for the link while
// MainView is switching tabs.
@MainActor
@Observable
final class PinExtractionLauncher {
    // Route payload driving `.navigationDestination(item:)` in the modifier.
    var pendingExtraction: PendingExtraction?
    var pasteError: String?
    var balance: Components.Schemas.ScanCreditBalanceDto?
    var showBuyCredits = false
    // Scan-credit pre-check gate for the paste-link flow. `creditGateError`
    // is the payload (analog of PinExtractionSessionService.lastCreditError);
    // `showCreditGate` is reconciled from it via .onChange inside
    // PinExtractionGateSheets, mirroring ProcessPinView's CreditPaywallSheets.
    var isCheckingCredits = false
    var showCreditGate = false
    var creditGateError: InsufficientScanCreditsError?
    var isShowingSubscription = false

    // Single available-credit count for the badge. Falls back to "0" when
    // offline so the user sees an unambiguous empty state. The full count is
    // shown — no upper cap — so large balances display in full.
    var creditLabel: String {
        String(max(balance?.available ?? 0, 0))
    }

    func loadBalance() async {
        do {
            let response = try await APIClient.shared.getPinExtractionQuota(.init())
            switch response {
            case .ok(let r):
                balance = try r.body.json
            case .undocumented:
                break
            }
        } catch {
            // Best-effort: silently keep the previous value (or the
            // placeholder) so the badge degrades gracefully offline.
        }
    }

    func openPastedLink(source: String = "paste") {
        // Validate the clipboard up front so we don't spin the credit gate for a
        // missing/unsupported link, and so a rapid second tap is rejected by the
        // guard inside startExtraction.
        guard !isCheckingCredits else { return }
        guard let clipboardText = UIPasteboard.general.string,
              let link = SupportedVideoLink.extract(from: clipboardText) else {
            pasteError = "Copy an Instagram or TikTok link first."
            return
        }
        startExtraction(for: link, source: source)
    }

    func resume(sessionId: String) {
        pendingExtraction = .resume(sessionId: sessionId)
    }

    // Shared entry for the paste button and the Share Extension hand-off:
    // gate on credits, then push ProcessPinView for a fresh extraction. The 402
    // backstop in ProcessPinView still covers the resume / race paths.
    func startExtraction(for link: String, source: String) {
        // In-flight flag set synchronously (before the Task) so a rapid second
        // trigger is rejected by the guard, not just the .disabled view.
        guard !isCheckingCredits else { return }
        isCheckingCredits = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let gate = await evaluateCreditGate()
            isCheckingCredits = false
            if let gate {
                // .onChange(of: creditGateError) in PinExtractionGateSheets
                // raises showCreditGate.
                creditGateError = gate
                return
            }
            AnalyticsClient.shared.track(
                .PIN_LINK_SUBMITTED,
                properties: [
                    "platform": SupportedVideoLink.platform(of: link),
                    "source": source,
                ]
            )
            pendingExtraction = .fresh(url: link)
        }
    }

    // nil ⇒ the user provably has ≥1 credit (open the pasted link).
    // Non-nil ⇒ block with QuotaExceededSheet. Per the confirmed product
    // decision an unknown / failed refresh blocks too — only an affirmative
    // available > 0 lets the flow through; the ProcessPinView 402 stays as
    // the backstop for the resume / race paths.
    private func evaluateCreditGate() async -> InsufficientScanCreditsError? {
        do {
            let response = try await APIClient.shared
                .getPinExtractionQuota(.init())
            switch response {
            case .ok(let r):
                let dto = try r.body.json
                balance = dto
                if dto.available > 0 { return nil }
                return Self.gateError(from: dto)
            case .undocumented:
                return Self.gateError(from: balance)
            }
        } catch {
            return Self.gateError(from: balance)
        }
    }

    // Builds the local error from the balance DTO. Deliberately does NOT use
    // ISO8601DateFormatter.withFractionalSeconds — that extension is private
    // to PinExtractionClient.swift. A parse miss degrades to nil and
    // QuotaExceededSheet falls back to its generic copy.
    private static func gateError(
        from balance: Components.Schemas.ScanCreditBalanceDto?
    ) -> InsufficientScanCreditsError {
        let next: Date? = balance?.nextProGrantAt.flatMap { iso in
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions =
                [.withInternetDateTime, .withFractionalSeconds]
            return withFrac.date(from: iso)
                ?? ISO8601DateFormatter().date(from: iso)
        }
        return InsufficientScanCreditsError(
            available: max(balance?.available ?? 0, 0),
            nextProGrantAt: next,
            canPurchase: true,
            message: String(localized: "You're out of scan credits.")
        )
    }
}

// Attaches everything the launcher needs on a host screen: the
// ProcessPinView navigation destination, the credit-gate sheet stack, and
// the paste-error alert. Kept as one modifier so BoardView/HomeView bodies
// stay within the Swift type-checker budget (same reason ProcessPinView
// extracted CreditPaywallSheets).
struct PinExtractionLauncherModifier: ViewModifier {
    @Bindable var launcher: PinExtractionLauncher
    let storeManager: StoreManager
    // Analytics context for SCAN_CREDITS_PAYWALL_VIEWED — e.g. "board_gate"
    // on the Board tab, "home_gate" on Home.
    let paywallContext: String

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $launcher.pendingExtraction) { pending in
                switch pending {
                case .fresh(let url):
                    ProcessPinView(sourceUrl: url)
                case .resume(let sessionId):
                    ProcessPinView(sessionId: sessionId)
                }
            }
            .modifier(
                PinExtractionGateSheets(
                    showCreditGate: $launcher.showCreditGate,
                    creditGateError: $launcher.creditGateError,
                    showBuyCredits: $launcher.showBuyCredits,
                    isShowingSubscription: $launcher.isShowingSubscription,
                    storeManager: storeManager,
                    paywallContext: paywallContext
                )
            )
            .alert("Couldn't open link", isPresented: Binding(
                get: { launcher.pasteError != nil },
                set: { if !$0 { launcher.pasteError = nil } }
            )) {
                Button("OK", role: .cancel) { launcher.pasteError = nil }
            } message: {
                Text(launcher.pasteError ?? "")
            }
    }
}

// Bundles the scan-credit pre-check sheets (QuotaExceededSheet → Buy credits /
// Upgrade) into one modifier. The button closures must NOT set
// `showCreditGate = false`; QuotaExceededSheet's own systemDismiss() closes
// the sheet and .onChange reconciles the bool — that is what avoids the
// double-dismiss / present-while-dismissing race.
private struct PinExtractionGateSheets: ViewModifier {
    @Binding var showCreditGate: Bool
    @Binding var creditGateError: InsufficientScanCreditsError?
    @Binding var showBuyCredits: Bool
    @Binding var isShowingSubscription: Bool
    let storeManager: StoreManager
    let paywallContext: String

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: $showCreditGate,
                onDismiss: {
                    // Swipe-to-dismiss cleanup. The buttons nil the payload
                    // before the sheet closes, so this only runs on a
                    // no-choice dismiss. Idempotent.
                    creditGateError = nil
                }
            ) {
                if let err = creditGateError {
                    QuotaExceededSheet(
                        error: err,
                        onBuyCredits: {
                            creditGateError = nil
                            showBuyCredits = true
                        },
                        onUpgrade: {
                            creditGateError = nil
                            isShowingSubscription = true
                        },
                        onDismiss: { creditGateError = nil }
                    )
                }
            }
            .sheet(isPresented: $showBuyCredits) {
                BuyVideoExtractionQuotaBottomSheet(
                    packages: ScanCreditPackPresenter.packages(
                        from: storeManager.scanPackProducts
                    ),
                    onPurchase: { pkg in
                        // Sync callback; the sheet dismisses itself
                        // immediately. The purchase runs in the background and
                        // the badge refreshes via .scanCreditBalanceChanged.
                        Task {
                            if let product = storeManager.scanPackProducts
                                .first(where: { $0.id == pkg.id }) {
                                try? await storeManager
                                    .purchaseScanCredits(product)
                            }
                        }
                    }
                )
                .onAppear {
                    AnalyticsClient.shared.track(
                        .SCAN_CREDITS_PAYWALL_VIEWED,
                        properties: ["context": paywallContext]
                    )
                }
            }
            .sheet(isPresented: $isShowingSubscription) {
                SubscriptionView()
            }
            .onChange(of: creditGateError) { _, newValue in
                showCreditGate = newValue != nil
            }
    }
}
