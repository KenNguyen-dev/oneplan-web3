import Foundation

struct PayQuote: Equatable {
    let recipientName: String
    let bankBin: String
    let accountNumber: String
    let amountVnd: UInt64
    let amountUsdcMicro: UInt64
    let feeMicro: UInt64
    let rate: String
    let needsApproval: Bool
}

struct PayRequest {
    let qrPayload: String
    let amountVnd: UInt64?
    let name: String
    let category: Components.Schemas.ExpenseCategory
    let shareWithUserIds: [Int]
}

enum PayOutcome: Equatable {
    /// Paid out and recorded as an expense.
    case confirmed(vaultTransactionId: Int)
    /// Submitted, but the payout provider has not answered yet. The server's
    /// reconcile job resolves it; the app must not retry.
    case pending
    /// Above the trip's threshold. Another member has to approve before it moves.
    case awaitingApproval(vaultTransactionId: Int)
}

enum VaultError: LocalizedError {
    case malformedAmount(String)
    case noVault
    case nothingToUpdate

    var errorDescription: String? {
        switch self {
        case .malformedAmount(let raw):
            return String(localized: "The server sent an amount this app cannot read: \(raw)")
        case .noVault:
            return String(localized: "This trip does not have a group wallet yet.")
        case .nothingToUpdate:
            return String(localized: "Nothing to update")
        }
    }
}

/// Drives every vault call.
///
/// Amounts cross the wire as decimal strings because micro-USDC exceeds what a
/// JSON number carries exactly. They are parsed here once and held as `UInt64`
/// everywhere else, so no screen ever does arithmetic on a `Double` balance.
///
/// Every transaction the server builds is checked by `TransactionVerifier`
/// before `WalletService` is allowed to sign it.
@MainActor
@Observable
final class TripVaultService {
    static let shared = TripVaultService()

    private(set) var balanceMicro: UInt64?
    private(set) var thresholdMicro: UInt64?
    private(set) var dailyLimitMicro: UInt64?
    private(set) var vaultPda: String?
    /// Vault USDC ATA — deposits land here and spends leave from here.
    private(set) var vaultUsdcAta: String?
    /// OnePlan treasury ATA that receives the 0.1% deposit skim.
    private(set) var treasuryAta: String?
    /// Receiver ATA for merchant spends (server-controlled payout wallet).
    private(set) var spendRecipientAta: String?
    private(set) var isLoading = false
    private(set) var lastError: String?
    /// Trip whose balance fields currently describe. Shared service — without
    /// this, opening a new trip briefly (or forever, if it has no vault yet)
    /// shows the previous trip's balance.
    private(set) var activeTripId: Int?

    /// Leave → Contribute handoff. Set before `vaultRequestContribute` so the
    /// first sheet open always locks amount (Notification userInfo alone raced).
    var pendingLeaveContributeMicro: UInt64?

    private var client: Client { APIClient.shared }

    private init() {}

    /// Drops cached chain fields so a different trip cannot inherit them.
    func resetBalanceState(for tripId: Int) {
        guard activeTripId != tripId else { return }
        activeTripId = tripId
        balanceMicro = nil
        thresholdMicro = nil
        dailyLimitMicro = nil
        vaultPda = nil
        vaultUsdcAta = nil
        treasuryAta = nil
        spendRecipientAta = nil
        lastError = nil
    }

    /// Clears balance after a trip with no vault (lazy create). Leaves
    /// `activeTripId` so the empty card stays empty until a real load.
    func clearBalance() {
        balanceMicro = nil
        thresholdMicro = nil
        dailyLimitMicro = nil
        vaultPda = nil
        vaultUsdcAta = nil
        treasuryAta = nil
        spendRecipientAta = nil
    }

    // MARK: - On-chain constants
    //
    // Copied from solana/target/idl/oneplan_vault.json. An Anchor discriminator
    // is sha256("global:<instruction>") truncated to eight bytes, so these are
    // reproducible rather than magic, and both were checked against the IDL.
    //
    // Deliberately hard-coded rather than fetched: they are what the app checks
    // the server's transactions against, so taking them from the server would
    // make the check circular.

    /// Devnet deployment. See solana/DEPLOY.md.
    static let programId = "8pjmDZvmRzjcSwzffqnsdzsPRb3nV9BiVDhGU3vmR7uD"
    static let depositDiscriminator: [UInt8] = [242, 35, 198, 137, 82, 225, 242, 182]
    static let spendDiscriminator: [UInt8] = [242, 205, 255, 87, 101, 217, 245, 57]
    /// Above the trip's threshold the server builds these two instead of
    /// `spend`: one to raise the proposal, one for the member who approves it.
    static let proposeSpendDiscriminator: [UInt8] = [63, 66, 131, 224, 13, 141, 135, 81]
    static let approveSpendDiscriminator: [UInt8] = [248, 201, 151, 15, 28, 162, 112, 90]
    /// Clears an open above-threshold spend without moving USDC.
    static let cancelSpendDiscriminator: [UInt8] = [122, 254, 101, 132, 241, 232, 205, 179]

    private func parse(_ value: String) throws -> UInt64 {
        guard let parsed = UInt64(value) else {
            throw VaultError.malformedAmount(value)
        }
        return parsed
    }

    // MARK: - Wallet

    /// Registers the embedded wallet so the vault can find this member.
    ///
    /// Wallet linking is per user, not per trip; `tripId` is only there because
    /// the route is nested under one.
    func linkWallet(publicKey: String, tripId: Int) async throws {
        _ = try await client.linkVaultWallet(
            .init(
                path: .init(tripId: tripId),
                body: .json(.init(publicKey: publicKey))
            )
        )
        .created
    }

    // MARK: - Balance

    /// Tells the screens the balance has moved.
    ///
    /// Raised by whatever moved it, never by reading it. Reading used to raise
    /// it, and every screen listening answered by reading again — so one read
    /// became an unbroken loop of them, across every member's device, until the
    /// RPC provider throttled the trip and ordinary payments started failing.
    private func announceBalanceChanged() {
        NotificationCenter.default.post(name: .vaultBalanceChanged, object: nil)
    }

    func loadBalance(tripId: Int) async throws {
        resetBalanceState(for: tripId)
        isLoading = true
        defer { isLoading = false }

        let body = try await client
            .getVaultBalance(.init(path: .init(tripId: tripId)))
            .ok.body.json

        balanceMicro = try parse(body.balanceMicro)
        thresholdMicro = try parse(body.thresholdMicro)
        dailyLimitMicro = try parse(body.dailyLimitMicro)
        vaultPda = body.vaultPda
        vaultUsdcAta = body.usdcAta
        treasuryAta = body.treasuryAta
        spendRecipientAta = body.spendRecipientAta
        lastError = nil
    }

    // MARK: - Create

    /// Creates the on-chain vault if this trip does not have one yet.
    ///
    /// Idempotent: the server returns the existing row when the vault is
    /// already there. Callers link the wallet first so `syncMembers` inside
    /// create can add this member before the first deposit.
    @discardableResult
    func ensureVault(tripId: Int) async throws -> Components.Schemas.VaultCreatedDto {
        try await client
            .createVault(
                .init(
                    path: .init(tripId: tripId),
                    body: .json(.init())
                )
            )
            .created.body.json
    }

    // MARK: - Deposit

    /// Builds, verifies, signs and submits a deposit.
    ///
    /// The submit step is what actually moves the money. Signing alone would
    /// leave the bytes on the device and the balance unchanged. A trip with no
    /// vault yet gets one here — there is no separate "enable" step.
    ///
    /// Returns the on-chain signature so the depositing UI can open the Move
    /// money receipt (Figma Processing / Done).
    @discardableResult
    func deposit(tripId: Int, amountMicro: UInt64) async throws -> String {
        let publicKey = try await WalletService.shared.ensureWallet()
        try await linkWallet(publicKey: publicKey, tripId: tripId)
        _ = try await ensureVault(tripId: tripId)

        // Refresh chain accounts before verifying — they are what the check
        // pins the unsigned transaction against.
        try await loadBalance(tripId: tripId)
        let wallet = try await myWallet(tripId: tripId)
        guard let owner = wallet.publicKey,
              let ownerAta = wallet.usdcAta,
              let vaultPda,
              let vaultUsdcAta,
              let treasuryAta
        else {
            throw VaultError.noVault
        }

        let unsigned = try await client.buildVaultDeposit(
            .init(
                path: .init(tripId: tripId),
                body: .json(.init(amountMicro: String(amountMicro)))
            )
        )
        .created.body.json.base64Tx

        try TransactionVerifier.verify(
            base64: unsigned,
            expectedProgramId: Self.programId,
            expectedDiscriminator: Self.depositDiscriminator,
            expectedAmountMicro: amountMicro,
            expectedAccounts: [vaultPda, vaultUsdcAta, treasuryAta, owner, ownerAta]
        )

        let signed = try await WalletService.shared.sign(base64Tx: unsigned)
        let submitted = try await client.submitVaultDeposit(
            .init(
                path: .init(tripId: tripId),
                body: .json(
                    .init(signedTx: signed, amountMicro: String(amountMicro))
                )
            )
        )
        .created.body.json

        try await loadBalance(tripId: tripId)
        announceBalanceChanged()
        return submitted.signature
    }

    /// Whether this trip has (or had) a vault, without disturbing loaded state.
    ///
    /// Uses balance because that endpoint is cheap and returns 200 for CLOSED
    /// vaults too (balance 0 after rent reclaim). A missing vault is 404 — the
    /// ordinary case for trips that never enabled the group wallet.
    func hasVault(tripId: Int) async -> Bool {
        do {
            _ = try await client
                .getVaultBalance(.init(path: .init(tripId: tripId)))
                .ok
            return true
        } catch {
            return false
        }
    }

    /// The caller's own wallet: the address to top up, and what it holds.
    func myWallet(
        tripId: Int
    ) async throws -> Components.Schemas.WalletBalanceDto {
        try await client
            .getMyWallet(.init(path: .init(tripId: tripId)))
            .ok.body.json
    }

    // MARK: - Read

    /// Deposits and payments, newest first.
    func loadHistory(tripId: Int) async throws -> [Components.Schemas.VaultHistoryEntryDto] {
        try await client
            .getVaultHistory(.init(path: .init(tripId: tripId)))
            .ok.body.json
    }

    /// The full receipt for one payment.
    func transactionDetail(
        tripId: Int,
        vaultTransactionId: Int
    ) async throws -> Components.Schemas.VaultTransactionDetailDto {
        try await client
            .getVaultTransaction(
                .init(
                    path: .init(
                        tripId: tripId,
                        vaultTransactionId: vaultTransactionId
                    )
                )
            )
            .ok.body.json
    }

    /// Edits name / category / share on a confirmed spend. Amount stays locked.
    func updateVaultSpend(
        tripId: Int,
        vaultTransactionId: Int,
        name: String?,
        category: Components.Schemas.ExpenseCategory?,
        shareWithUserIds: [Int]?
    ) async throws -> Components.Schemas.VaultTransactionDetailDto {
        if name == nil && category == nil && shareWithUserIds == nil {
            throw VaultError.nothingToUpdate
        }
        return try await client
            .updateVaultSpend(
                .init(
                    path: .init(
                        tripId: tripId,
                        vaultTransactionId: vaultTransactionId
                    ),
                    body: .json(
                        .init(
                            name: name,
                            category: category.map { .init(value1: $0) },
                            shareWithUserIds: shareWithUserIds
                        )
                    )
                )
            )
            .ok.body.json
    }

    // MARK: - Settlement

    /// Who is owed what if the vault were wound up now.
    func settlementPreview(
        tripId: Int
    ) async throws -> Components.Schemas.SettlementPreviewDto {
        try await client
            .getVaultSettlement(.init(path: .init(tripId: tripId)))
            .ok.body.json
    }

    /// Confirms a cash debt was received.
    ///
    /// Only the creditor may call this; the server refuses anyone else. The app
    /// hides the button for other people so the refusal is never reached in
    /// normal use, but the server is the one enforcing it.
    func confirmCashDebt(tripId: Int, fromUserId: Int) async throws {
        _ = try await client.confirmVaultCashDebt(
            .init(
                path: .init(tripId: tripId),
                body: .json(.init(fromUserId: fromUserId))
            )
        )
        .created
    }

    // MARK: - Pay

    /// Who a scanned code pays, before any amount is known.
    ///
    /// Separate from `quote` because quoting needs an amount and most shop codes
    /// carry none, yet the name has to be on screen while the amount is typed.
    func lookupRecipient(
        tripId: Int,
        qrPayload: String
    ) async throws -> Components.Schemas.RecipientDto {
        try await client.lookupVaultRecipient(
            .init(
                path: .init(tripId: tripId),
                body: .json(.init(qrPayload: qrPayload))
            )
        )
        .created.body.json
    }

    func quote(
        tripId: Int,
        qrPayload: String,
        amountVnd: UInt64?
    ) async throws -> PayQuote {
        let body = try await client.quoteVaultPayment(
            .init(
                path: .init(tripId: tripId),
                body: .json(
                    .init(
                        qrPayload: qrPayload,
                        amountVnd: amountVnd.map(String.init)
                    )
                )
            )
        )
        .created.body.json

        return PayQuote(
            recipientName: body.recipientName,
            bankBin: body.bankBin,
            accountNumber: body.accountNumber,
            amountVnd: try parse(body.amountVnd),
            amountUsdcMicro: try parse(body.amountUsdcMicro),
            feeMicro: try parse(body.feeMicro),
            rate: body.rate,
            needsApproval: body.needsApproval
        )
    }

    /// Records the payment, verifies the transaction, signs it and submits.
    ///
    /// A payment over the trip's threshold comes back as `.awaitingApproval`
    /// without being signed here: it needs a second member first.
    func pay(tripId: Int, request: PayRequest) async throws -> PayOutcome {
        let prepared = try await client.prepareVaultPayment(
            .init(
                path: .init(tripId: tripId),
                body: .json(
                    .init(
                        qrPayload: request.qrPayload,
                        amountVnd: request.amountVnd.map(String.init),
                        name: request.name,
                        category: .init(value1: request.category),
                        shareWithUserIds: request.shareWithUserIds
                    )
                )
            )
        )
        .created.body.json

        if prepared.needsApproval {
            // The proposal is a transaction like any other and has to be signed
            // and submitted. Returning here without doing so left the approval
            // with no account to approve — the payment could never complete.
            // Signing it also counts as the proposer's own approval on chain.
            _ = try await signAndSubmit(
                tripId: tripId,
                vaultTransactionId: Int(prepared.vaultTransactionId),
                unsigned: prepared.base64Tx,
                expecting: Self.proposeSpendDiscriminator
            )
            return .awaitingApproval(
                vaultTransactionId: Int(prepared.vaultTransactionId)
            )
        }

        let status = try await signAndSubmit(
            tripId: tripId,
            vaultTransactionId: Int(prepared.vaultTransactionId),
            unsigned: prepared.base64Tx
        )
        try await loadBalance(tripId: tripId)
        announceBalanceChanged()
        return status
    }

    /// Adds the caller's approval to a payment that needed a second signature.
    func approve(tripId: Int, vaultTransactionId: Int) async throws -> PayOutcome {
        let unsigned = try await client.approveVaultPayment(
            .init(
                path: .init(
                    tripId: tripId,
                    vaultTransactionId: vaultTransactionId
                )
            )
        )
        .created.body.json.base64Tx

        let status = try await signAndSubmit(
            tripId: tripId,
            vaultTransactionId: vaultTransactionId,
            unsigned: unsigned,
            expecting: Self.approveSpendDiscriminator
        )
        try await loadBalance(tripId: tripId)
        announceBalanceChanged()
        return status
    }

    /// Drops an open above-threshold proposal. Proposer or host / co-host.
    ///
    /// Does not move USDC — only clears the on-chain spend slot so another
    /// payment can be raised.
    func cancel(tripId: Int, vaultTransactionId: Int) async throws {
        let unsigned = try await client.cancelVaultPayment(
            .init(
                path: .init(
                    tripId: tripId,
                    vaultTransactionId: vaultTransactionId
                )
            )
        )
        .created.body.json.base64Tx

        try await loadBalance(tripId: tripId)
        guard let vaultPda else { throw VaultError.noVault }
        guard let signer = WalletService.shared.publicKey else {
            throw WalletError.notConfigured
        }

        try TransactionVerifier.verify(
            base64: unsigned,
            expectedProgramId: Self.programId,
            expectedDiscriminator: Self.cancelSpendDiscriminator,
            expectedAmountMicro: nil,
            expectedAccounts: [vaultPda, signer]
        )

        let signed = try await WalletService.shared.sign(base64Tx: unsigned)
        _ = try await client.submitVaultPaymentCancel(
            .init(
                path: .init(
                    tripId: tripId,
                    vaultTransactionId: vaultTransactionId
                ),
                body: .json(.init(signedTx: signed))
            )
        )
        .created

        announceBalanceChanged()
    }

    private func signAndSubmit(
        tripId: Int,
        vaultTransactionId: Int,
        unsigned: String,
        expecting discriminator: [UInt8] = TripVaultService.spendDiscriminator
    ) async throws -> PayOutcome {
        try await loadBalance(tripId: tripId)
        guard let vaultPda, let spendRecipientAta else {
            throw VaultError.noVault
        }
        guard let signer = WalletService.shared.publicKey else {
            throw WalletError.notConfigured
        }

        // propose_spend does not touch the vault ATA; spend and approve_spend do.
        var expected = [vaultPda, spendRecipientAta, signer]
        if discriminator != Self.proposeSpendDiscriminator {
            guard let vaultUsdcAta else { throw VaultError.noVault }
            expected.append(vaultUsdcAta)
        }

        try TransactionVerifier.verify(
            base64: unsigned,
            expectedProgramId: Self.programId,
            expectedDiscriminator: discriminator,
            expectedAmountMicro: nil,
            expectedAccounts: expected
        )

        let signed = try await WalletService.shared.sign(base64Tx: unsigned)
        let result = try await client.submitVaultPayment(
            .init(
                path: .init(
                    tripId: tripId,
                    vaultTransactionId: vaultTransactionId
                ),
                body: .json(.init(signedTx: signed))
            )
        )
        .created.body.json

        // PENDING means the payout provider has not answered. The server's
        // reconcile job owns it from here; retrying would pay twice.
        return result.status == "CONFIRMED"
            ? .confirmed(vaultTransactionId: vaultTransactionId)
            : .pending
    }
}

extension Notification.Name {
    static let vaultBalanceChanged = Notification.Name("vaultBalanceChanged")

    /// Repeat a payment to a recipient the trip has already paid.
    ///
    /// Carries the QR payload as the notification object. The history now lives
    /// in the trip's own History tab, while the code that pays lives on the
    /// vault card above it, so the two talk through this rather than the tab
    /// growing a second copy of the payment flow.
    static let vaultSendAgain = Notification.Name("vaultSendAgain")

    /// Ask the trip vault card to open Move token / contribute (optional amountMicro).
    static let vaultRequestContribute = Notification.Name("vaultRequestContribute")

    /// A payment above the trip's limit is waiting for a second signature.
    /// Carries tripId, vaultTransactionId, amountVnd and recipientName.
    static let vaultApprovalRequested = Notification.Name("vaultApprovalRequested")

    /// Vault settlement proposed or an approval landed. Carries tripId.
    static let vaultSettlementUpdated = Notification.Name("vaultSettlementUpdated")

    /// End-trip consensus progress. Carries tripId, status, approvedCount,
    /// memberCount, and optional deniedByUserId.
    static let tripEndRequestUpdated = Notification.Name("tripEndRequestUpdated")

    /// Member announced vault leave. Carries tripId and userId (leaver).
    static let vaultLeaveRequested = Notification.Name("vaultLeaveRequested")

    /// Leave-settle deposit confirmed on-chain. Carries tripId as object.
    /// Trip detail auto-announces and opens the waiting-for-host leave sheet.
    static let vaultLeaveDepositCompleted = Notification.Name("vaultLeaveDepositCompleted")

    /// Member removed from trip. Carries tripId, userId, displayName.
    static let tripMemberRemoved = Notification.Name("tripMemberRemoved")
}
