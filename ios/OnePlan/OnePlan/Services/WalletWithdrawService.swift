import Foundation
import Observation

/// The member's own wallet, outside any trip.
///
/// Kept apart from `TripVaultService`, which is always about one trip's money.
/// This is about the member's, and the settings screen that reaches it does not
/// belong to a trip at all.
@MainActor
@Observable
final class WalletWithdrawService {
    static let shared = WalletWithdrawService()

    private var client: Client { APIClient.shared }

    struct Wallet {
        let publicKey: String
        let balanceMicro: String
    }

    struct RecipientCheck {
        let address: String
        /// True when the address has never held USDC.
        let isNew: Bool
    }

    func myWallet() async throws -> Wallet {
        let body = try await client.getWallet(.init()).ok.body.json
        // Absent until the member has linked one, which is the state the
        // settings row shows as blank rather than as an error.
        return Wallet(
            publicKey: body.publicKey ?? "",
            balanceMicro: body.balanceMicro
        )
    }

    /// Recent USDC transfers on this wallet's ATA (server reads Solana).
    func history() async throws -> [Components.Schemas.WalletHistoryEntryDto] {
        try await client.getWalletHistory(.init()).ok.body.json
    }

    func inspectRecipient(address: String) async throws -> RecipientCheck {
        let body = try await client
            .inspectWithdrawRecipient(.init(body: .json(.init(address: address))))
            .ok.body.json
        return RecipientCheck(address: body.address, isNew: body.isNew)
    }

    /// Signs and sends a withdrawal.
    ///
    /// The transaction is checked before it is signed, as every other one is.
    /// There is no amount assertion here: the server was told the amount and
    /// built the transfer from it, and the instruction being a token transfer
    /// is what a swapped transaction would have to change.
    func withdraw(address: String, amountMicro: UInt64) async throws -> WalletWithdrawResult {
        let built = try await client.buildWithdrawal(
            .init(
                body: .json(
                    .init(address: address, amountMicro: String(amountMicro))
                )
            )
        )
        .created.body.json

        let signed = try await WalletService.shared.sign(base64Tx: built.base64Tx)
        let result = try await client
            .submitWithdrawal(.init(body: .json(.init(signedTx: signed))))
            .created.body.json

        return WalletWithdrawResult(
            // PENDING means the transfer reached the chain and its confirmation
            // did not reach us. The money has moved either way, so this is
            // never reported as a failure.
            status: result.status == "CONFIRMED" ? .completed : .processing,
            amountMicro: amountMicro,
            recipient: address,
            signature: result.signature,
            date: Date()
        )
    }
}
