import SwiftUI

/// The whole vault flow for a trip, behind one view.
///
/// Owning the card, the sheets and the navigation here keeps `TripDetailView`
/// to a single conditional: a 1600 line screen should not also learn how a
/// payment is composed.
struct TripVaultSection: View {
    let tripId: Int
    let tripName: String
    let coverImageUrl: String?
    let currency: Currency
    let members: [TripMemberDto]
    /// End-trip consensus is PENDING — card CTA becomes Waiting for approval.
    var isWaitingForEndApproval: Bool = false
    /// Caller still needs to Approve/Deny the pending end request.
    var needsEndTripReview: Bool = false
    var onWaitingForApproval: () -> Void = {}

    @State private var vault = TripVaultService.shared
    @Environment(UserProfileService.self) private var userProfileService
    @State private var isShowingDepositOptions = false
    /// Set while the options sheet is closing, read once it has closed.
    ///
    /// Presenting the wallet in the same frame that dismisses the options loses
    /// it — UIKit is still tearing the first sheet down and drops the second.
    @State private var wantsOnchainDeposit = false
    /// Item-based contribute sheet so leave lock amount is on the request
    /// itself (`.sheet(isPresented:)` + separate prefill state raced to keypad).
    @State private var contributeSheet: VaultContributeSheetRequest?
    @State private var isShowingScanner = false
    @State private var pending: PendingPayment?
    @State private var errorMessage: String?
    /// Pay / approve still use a blocking overlay. Deposits use
    /// `VaultDepositingSheet` instead (Figma Depositing).
    @State private var isWorking = false
    @State private var successMessage: String?
    /// In-flight deposit: overlay on Contribute in the same sheet so Processing
    /// shows before createVault without dismissing/re-presenting.
    @State private var depositFlow: VaultDepositFlow?
    /// Contribute stays `.large`; Depositing shrinks to a compact bottom sheet.
    /// Both detents stay registered so selection can change without swapping
    /// the detent *set* (that flash-resized to an empty body).
    @State private var depositSheetDetent: PresentationDetent = .large
    @State private var isDepositResultPresented = false
    /// Set while the depositing sheet closes so Details can open Processing/Done
    /// after UIKit finishes tearing the sheet down.
    @State private var wantsDepositResult = false
    /// Same handoff for Done → amount sheet (Deposit again).
    @State private var wantsDepositAgain = false
    /// A payment someone else raised that is waiting on a signature from here.
    @State private var approvalRequest: ApprovalRequest?
    /// Opened after a payment actually settles (under-threshold pay, or the
    /// second signature that finishes an over-threshold one).
    @State private var paidDetail: Components.Schemas.VaultTransactionDetailDto?
    /// Set while the pay cover closes; receipt opens only in that cover's
    /// onDismiss so Edit's fullScreenCover is not nested under a half-torn-down
    /// pay presentation (History → TX → Edit works; auto-open after pay did not).
    @State private var pendingPaidDetailId: Int?

    /// Opens Move-token / contribute. `lockedAmountMicro` non-nil = leave settle
    /// (amount fixed, no keypad).
    private struct VaultContributeSheetRequest: Identifiable {
        let id = UUID()
        let lockedAmountMicro: UInt64?
    }

    private struct ApprovalRequest: Identifiable {
        let id: Int
        let amountVnd: UInt64
        let recipientName: String
    }

    /// A scanned code on its way to becoming a payment.
    private struct PendingPayment: Identifiable {
        let id = UUID()
        let payload: String
        let decoded: VietQRPayload
        var recipientName: String?
        var amountVnd: UInt64?
    }

    private var balanceUsdc: Double {
        Double(vault.balanceMicro ?? 0) / 1_000_000
    }

    /// The card shows the home-currency value, which needs a rate. Until a quote
    /// supplies one the USDC figure is the only honest number, so the converted
    /// line reads zero rather than guessing.
    private var balanceInTripCurrency: Double {
        balanceUsdc * Self.indicativeRate
    }

    /// Only used for the indicative line while typing. Every binding number
    /// comes from the server at quote time.
    private static let indicativeRate: Double = 26_500

    var body: some View {
        TripVaultCard(
            tripName: tripName,
            coverImageUrl: coverImageUrl,
            balance: balanceInTripCurrency,
            currency: currency,
            balanceUsdc: balanceUsdc,
            isWaitingForEndApproval: isWaitingForEndApproval,
            needsEndTripReview: needsEndTripReview,
            onDeposit: { isShowingDepositOptions = true },
            onScanQR: { isShowingScanner = true },
            onWaitingForApproval: onWaitingForApproval
        )
        .overlay(alignment: .top) {
            // Same chrome as DepositToOnePlanWalletView copied toast — neutral,
            // not brand-green. Own deposits still skip this (sheet / Move money).
            if let successMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                    Text(successMessage)
                        .font(Font.beVietnamPro(15))
                        .tracking(-0.3)
                }
                .foregroundStyle(Constants.White)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Constants.Neutral900.opacity(0.92), in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.snappy(duration: 0.25), value: successMessage)
        .task { await refresh() }
        .alert(
            "Deposit failed",
            isPresented: Binding(
                get: { errorMessage != nil && pending == nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(errorMessage ?? "") }
        )
        .onReceive(NotificationCenter.default.publisher(for: .vaultBalanceChanged)) { note in
            Task { await refresh() }
            // Somebody else moved the money. Refreshing alone changes a number
            // nobody was watching; this says what happened. The member who did
            // it already got their own confirmation and does not need a second.
            guard let info = note.userInfo,
                  info["tripId"] as? Int == tripId,
                  let kind = info["kind"] as? String,
                  let me = userProfileService.profile?.id,
                  info["actorUserId"] as? Int != me
            else { return }
            Task {
                await announce(
                    Self.movementText(
                        kind: kind,
                        actor: info["actorName"] as? String ?? "",
                        amountMicro: UInt64(info["amountMicro"] as? String ?? "") ?? 0
                    )
                )
            }
        }
        // Send again, raised from a receipt in the History tab below. Straight
        // to the amount: the recipient is already known, so making someone point
        // a camera at the same code again would be asking for information the
        // receipt already has.
        .onReceive(NotificationCenter.default.publisher(for: .vaultSendAgain)) { note in
            guard let payload = note.object as? String,
                  let decoded = try? VietQRDecoder.decode(payload) else { return }
            pending = PendingPayment(payload: payload, decoded: decoded)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .vaultRequestContribute)
        ) { note in
            guard (note.object as? Int) == tripId else { return }
            // Prefer service handoff (leave settle). Never open free keypad
            // from this notification without a lock amount.
            let locked = vault.pendingLeaveContributeMicro
                ?? Self.amountMicro(from: note.userInfo)
            vault.pendingLeaveContributeMicro = nil
            guard let locked, locked > 0 else { return }
            presentContribute(lockedAmountMicro: locked)
        }
        // Someone else's payment is held up waiting for a second signature. It
        // is asked for rather than left in the history, because until somebody
        // signs it the money has not moved and the merchant has not been paid.
        .onReceive(
            NotificationCenter.default.publisher(for: .vaultApprovalRequested)
        ) { note in
            guard let info = note.userInfo,
                  info["tripId"] as? Int == tripId,
                  let id = info["vaultTransactionId"] as? Int
            else { return }
            // The broadcast reaches the whole trip, so each device decides for
            // itself whether the question is for them. Two ways it is not: the
            // chain refuses a second signature from whoever raised it, and a
            // trip that has named its approvers refuses everybody else.
            guard let me = userProfileService.profile?.id,
                  info["proposedByUserId"] as? Int != me
            else { return }
            if let approvers = info["approverUserIds"] as? [Int],
               !approvers.contains(me) {
                return
            }
            approvalRequest = ApprovalRequest(
                id: id,
                amountVnd: UInt64(info["amountVnd"] as? String ?? "") ?? 0,
                recipientName: info["recipientName"] as? String ?? ""
            )
        }
        .alert(item: $approvalRequest) { request in
            Alert(
                title: Text("Approval needed"),
                message: Text(
                    "\(CurrencyFormatter.formatWhole(Double(request.amountVnd))) to \(request.recipientName) is over the trip limit."
                ),
                primaryButton: .default(Text("Approve")) {
                    Task { await approve(vaultTransactionId: request.id) }
                },
                secondaryButton: .cancel(Text("Not now"))
            )
        }
        // Which way the money comes in is asked first. Today only one answer
        // works, and saying so is the point: the chain is one route in, not the
        // whole idea of putting money in.
        .sheet(
            isPresented: $isShowingDepositOptions,
            onDismiss: {
                guard wantsOnchainDeposit else { return }
                wantsOnchainDeposit = false
                presentContribute(lockedAmountMicro: nil)
            }
        ) {
            DepositOptionsSheet {
                wantsOnchainDeposit = true
                isShowingDepositOptions = false
            }
            .presentationDetents([.height(340)])
            .presentationCornerRadius(44)
        }
        .sheet(
            item: $contributeSheet,
            onDismiss: {
                // Details → Move money receipt after this sheet is gone.
                if wantsDepositResult {
                    wantsDepositResult = false
                    isDepositResultPresented = true
                    return
                }
                // Cancelled Contribute or dismissed wait sheet — drop the flow
                // unless the result cover already owns it.
                if !isDepositResultPresented {
                    depositFlow = nil
                }
            }
        ) { request in
            // Same sheet for Contribute → Depositing (no dismiss/re-present).
            // Selection moves .large → compact; both stay in the detent set.
            Group {
                if let flow = depositFlow {
                    VaultDepositingSheet(
                        amountMicro: flow.amountMicro,
                        fromAddress: flow.fromAddress,
                        toAddress: flow.toAddress,
                        onDetails: {
                            wantsDepositResult = true
                            contributeSheet = nil
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Constants.White)
                    .interactiveDismissDisabled(flow.status == .processing)
                } else {
                    ContributeToVaultView(
                        tripId: tripId,
                        prefilledAmountMicro: request.lockedAmountMicro,
                        locksAmount: request.lockedAmountMicro != nil
                    ) { amountMicro in
                        beginDepositing(amountMicro: amountMicro)
                        Task { await completeContribute(amountMicro: amountMicro) }
                    }
                }
            }
            .presentationDetents(
                [.large, Self.depositingDetent],
                selection: $depositSheetDetent
            )
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(48)
            .presentationBackground(Constants.White)
            .interactiveDismissDisabled(depositFlow?.status == .processing)
            .onAppear {
                if depositFlow == nil {
                    depositSheetDetent = .large
                }
            }
        }
        // Figma Processing / Done — Details from the wait sheet.
        .fullScreenCover(isPresented: $isDepositResultPresented, onDismiss: {
            depositFlow = nil
            guard wantsDepositAgain else { return }
            wantsDepositAgain = false
            presentContribute(lockedAmountMicro: nil)
        }) {
            if let flow = depositFlow {
                VaultDepositResultView(
                    flow: flow,
                    onDone: { isDepositResultPresented = false },
                    onDepositAgain: {
                        wantsDepositAgain = true
                        isDepositResultPresented = false
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $isShowingScanner) {
            VaultScanQRView(
                onScanned: { decoded, payload in
                    isShowingScanner = false
                    pending = PendingPayment(payload: payload, decoded: decoded)
                },
                onCancel: { isShowingScanner = false }
            )
        }
        .fullScreenCover(
            item: $pending,
            onDismiss: {
                guard let id = pendingPaidDetailId else { return }
                pendingPaidDetailId = nil
                Task { await openPaidDetail(id) }
            }
        ) { payment in
            payFlow(for: payment)
        }
        .sheet(item: $paidDetail) { detail in
            VaultTransactionDetailView(
                detail: Self.mapPaidDetail(detail),
                tripId: tripId,
                vaultTransactionId: detail.id,
                members: members,
                allowsEditing: detail.canEdit,
                onBack: { paidDetail = nil },
                onSendAgain: detail.qrPayload.map { payload in
                    {
                        paidDetail = nil
                        NotificationCenter.default.post(
                            name: .vaultSendAgain,
                            object: payload
                        )
                    }
                },
                onEdited: { updated, _ in
                    paidDetail = updated
                }
            )
            .presentationDetents([.large])
            .presentationCornerRadius(48)
        }
    }

    /// The amount screen stays mounted and the expense sheet rides on top of
    /// it, which is how the design shows the figure while the details are
    /// filled in — and it means the typed amount survives dismissing the sheet,
    /// because the screen holding it never went away.
    private func payFlow(for payment: PendingPayment) -> some View {
        VaultPayAmountView(
            recipientName: payment.recipientName ?? "…",
            balanceVnd: balanceInTripCurrency,
            prefilledAmountVnd: payment.decoded.amountVnd,
            indicativeRate: Self.indicativeRate,
            onBack: { pending = nil },
            onNext: { amount in pending?.amountVnd = amount }
        )
        .task { await loadRecipient(for: payment) }
        .overlay { workingOverlay }
        // The alert lives here rather than on the card: the card is underneath
        // this cover, and an alert on a covered view never appears — which is
        // how a failing payment looked like a button that did nothing.
        .alert(
            "Payment failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(errorMessage ?? "") }
        )
        .sheet(
            isPresented: Binding(
                get: { pending?.amountVnd != nil },
                // Pulling the sheet down returns to the amount, rather than
                // trapping the user with no way back.
                set: { if !$0 { pending?.amountVnd = nil } }
            )
        ) {
            VaultExpenseSheet(
                members: members,
                fallbackName: payment.recipientName ?? ""
            ) { details in
                guard let amount = pending?.amountVnd else { return }
                Task { await submit(payment: payment, amountVnd: amount, details: details) }
            }
            .presentationDetents([.fraction(0.56)])
            .presentationBackgroundInteraction(.enabled)
            // The sheet is the topmost thing on screen while the payment runs,
            // so this is the only place the progress can actually be seen. On
            // the cover underneath it was covered by this very sheet, which is
            // why Done looked like it did nothing at all.
            .overlay { workingOverlay }
        }
    }

    @ViewBuilder
    private var workingOverlay: some View {
        if isWorking {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large).tint(Constants.White)
                    Text("Paying…")
                        .font(Font.beVietnamPro(15))
                        .foregroundStyle(Constants.White)
                }
            }
            .transition(.opacity)
            .animation(.snappy(duration: 0.2), value: isWorking)
        }
    }

    /// Adds this member's signature, which is the one that moves the money.
    private func approve(vaultTransactionId: Int) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let outcome = try await vault.approve(
                tripId: tripId,
                vaultTransactionId: vaultTransactionId
            )
            switch outcome {
            case .confirmed(let id):
                await openPaidDetail(id)
            case .pending, .awaitingApproval:
                await announce("Approved")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let depositingDetent = PresentationDetent.height(340)

    /// Notification `userInfo` may box amount as String / NSNumber / UInt64.
    private static func amountMicro(from userInfo: [AnyHashable: Any]?) -> UInt64? {
        guard let userInfo else { return nil }
        if let s = userInfo["amountMicro"] as? String {
            return UInt64(s)
        }
        if let n = userInfo["amountMicro"] as? NSNumber {
            return n.uint64Value
        }
        return userInfo["amountMicro"] as? UInt64
    }

    private func presentContribute(lockedAmountMicro: UInt64?) {
        depositFlow = nil
        depositSheetDetent = .large
        // New id every open so leave-lock content cannot reuse a free keypad sheet.
        contributeSheet = VaultContributeSheetRequest(
            lockedAmountMicro: lockedAmountMicro
        )
    }

    /// Swaps Contribute → Depositing in the same sheet before any await.
    private func beginDepositing(amountMicro: UInt64) {
        let from = WalletService.shared.publicKey ?? "…"
        let to = vault.vaultPda ?? "…"
        depositFlow = VaultDepositFlow(
            amountMicro: amountMicro,
            fromAddress: from,
            toAddress: to
        )
        withAnimation(.snappy(duration: 0.28)) {
            depositSheetDetent = Self.depositingDetent
        }
    }

    private func completeContribute(amountMicro: UInt64) async {
        do {
            var publicKey = WalletService.shared.publicKey
            var toAddress = vault.vaultPda
            if publicKey == nil || toAddress == nil {
                publicKey = try await WalletService.shared.ensureWallet()
                try await vault.linkWallet(publicKey: publicKey!, tripId: tripId)
                _ = try await vault.ensureVault(tripId: tripId)
                try await vault.loadBalance(tripId: tripId)
                toAddress = vault.vaultPda
            }
            guard let publicKey, let toAddress else {
                throw VaultError.noVault
            }

            if let flow = depositFlow {
                flow.fromAddress = publicKey
                flow.toAddress = toAddress
            } else {
                beginDepositing(amountMicro: amountMicro)
                depositFlow?.fromAddress = publicKey
                depositFlow?.toAddress = toAddress
            }

            let signature = try await vault.deposit(
                tripId: tripId,
                amountMicro: amountMicro
            )
            depositFlow?.signature = signature
            depositFlow?.status = .completed

            // Leave settle: skip Move-money receipt → announce + waiting sheet.
            if contributeSheet?.lockedAmountMicro != nil {
                contributeSheet = nil
                wantsDepositResult = false
                wantsDepositAgain = false
                isDepositResultPresented = false
                depositFlow = nil
                NotificationCenter.default.post(
                    name: .vaultLeaveDepositCompleted,
                    object: tripId
                )
            }
        } catch {
            contributeSheet = nil
            isDepositResultPresented = false
            wantsDepositResult = false
            wantsDepositAgain = false
            depositFlow = nil
            errorMessage = error.localizedDescription
        }
    }

    /// What to say when the wallet moved without this member doing it.
    ///
    /// A settlement names no actor: it is the whole group's, and the two who
    /// signed it are not more responsible for it than anybody else.
    private static func movementText(
        kind: String,
        actor: String,
        amountMicro: UInt64
    ) -> String {
        let usdc = String(format: "%.2f USDC", Double(amountMicro) / 1_000_000)
        switch kind {
        case "DEPOSIT":
            return actor.isEmpty
                ? String(localized: "\(usdc) added to the group")
                : String(localized: "\(actor) added \(usdc)")
        case "SETTLEMENT":
            return String(localized: "The group wallet was settled")
        default:
            return actor.isEmpty
                ? String(localized: "\(usdc) paid from the group")
                : String(localized: "\(actor) paid \(usdc)")
        }
    }

    /// Shows a confirmation briefly. The balance updating underneath is the
    /// real proof, but it is easy to miss when the number was already changing.
    private func announce(_ message: String) async {
        successMessage = message
        try? await Task.sleep(for: .seconds(3))
        successMessage = nil
    }

    private func refresh() async {
        // Drop the previous trip's balance immediately — this service is shared
        // and a trip with no vault yet never overwrites those fields otherwise.
        vault.resetBalanceState(for: tripId)

        // The wallet is created and registered here rather than at sign-in:
        // linking needs a trip id, and a member who never opens a vault should
        // not have one made for them.
        do {
            let publicKey = try await WalletService.shared.ensureWallet()
            try await vault.linkWallet(publicKey: publicKey, tripId: tripId)
        } catch {
            // Non-fatal. The balance still renders; deposits and payments will
            // surface the real error when they are attempted.
            print("TripVaultSection wallet setup: \(error)")
        }

        do {
            try await vault.loadBalance(tripId: tripId)
        } catch {
            // A trip without a vault is the normal case, not an error worth
            // interrupting the screen for. Clear so we do not keep showing
            // another trip's balance under this card.
            vault.clearBalance()
            print("TripVaultSection.refresh: \(error)")
        }
    }

    /// Fetches the recipient's real name, which comes from the bank rather than
    /// from the QR code. Pricing cannot answer this: it needs an amount, and
    /// this screen exists to collect one.
    private func loadRecipient(for payment: PendingPayment) async {
        guard pending?.recipientName == nil else { return }
        do {
            let found = try await vault.lookupRecipient(
                tripId: tripId,
                qrPayload: payment.payload
            )
            pending?.recipientName = found.recipientName
        } catch {
            print("TripVaultSection.loadRecipient: \(error)")
        }
    }

    private func submit(
        payment: PendingPayment,
        amountVnd: UInt64,
        details: VaultExpenseDetails
    ) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let outcome = try await vault.pay(
                tripId: tripId,
                request: PayRequest(
                    qrPayload: payment.payload,
                    amountVnd: amountVnd,
                    name: details.name,
                    category: apiCategory(for: details.category),
                    shareWithUserIds: details.shareWithUserIds
                )
            )
            pending = nil
            switch outcome {
            case .confirmed(let id):
                // Do not present the receipt in this frame — wait for the pay
                // cover's onDismiss (see pendingPaidDetailId).
                pendingPaidDetailId = id
            case .pending:
                // The chain leg landed but the payout has not answered. The
                // server's reconcile job owns it now, and saying "failed" would
                // invite a retry that pays twice.
                await announce("Sent. Waiting on the bank to confirm.")
            case .awaitingApproval:
                // Not a failure, so not the error alert — and the alert it used
                // to raise hung off the cover this line has just dismissed, so
                // it never appeared anyway. The balance deliberately does not
                // move: nothing has left the vault until a second member signs.
                await announce("Over the trip limit. Waiting for a member to approve.")
            }
        } catch {
            // Left on screen on purpose: the cover carries the alert, and a
            // failed payment should keep the amount and the details so it can be
            // sent again without typing them a second time.
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the receipt and presents it. Used only when the payment has
    /// actually settled — not for pending bank confirm or awaiting approval.
    private func openPaidDetail(_ vaultTransactionId: Int) async {
        do {
            paidDetail = try await vault.transactionDetail(
                tripId: tripId,
                vaultTransactionId: vaultTransactionId
            )
        } catch {
            // Payment already succeeded; falling back to a toast is better than
            // implying the pay itself failed.
            await announce("Paid")
            errorMessage = error.localizedDescription
        }
    }

    private static func mapPaidDetail(
        _ detail: Components.Schemas.VaultTransactionDetailDto
    ) -> VaultTransactionDetail {
        VaultTransactionDetailView.map(detail)
    }

    /// Exhaustive by construction: `apiValue` is the single source shared with
    /// the server, so a new category cannot fall through to OTHER here.
    private func apiCategory(
        for category: CategoryChip.Category
    ) -> Components.Schemas.ExpenseCategory {
        Components.Schemas.ExpenseCategory(rawValue: category.apiValue) ?? .OTHER
    }
}
