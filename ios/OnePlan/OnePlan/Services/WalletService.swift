import Foundation
import PrivySDK

enum WalletError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case sessionFailed(String)
    case creationFailed(String)
    case malformedTransaction
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "Wallet is not configured for this build.")
        case .notAuthenticated:
            return String(localized: "Sign in before using the group wallet.")
        case .sessionFailed(let reason):
            return String(localized: "Could not reach the wallet service: \(reason)")
        case .creationFailed(let reason):
            return String(localized: "Could not create your wallet: \(reason)")
        case .malformedTransaction:
            return String(localized: "The server returned a transaction this app cannot read.")
        case .signingFailed(let reason):
            return String(localized: "Could not sign: \(reason)")
        }
    }
}

/// Owns the embedded Solana wallet and is the only place in the app that
/// produces a signature.
///
/// The user never sees a seed phrase and never installs a wallet app: they sign
/// in as before and the key material lives with Privy.
///
/// Everything SDK-specific is behind this class, so swapping Privy for Turnkey
/// or Web3Auth touches this file and nothing else.
@MainActor
@Observable
final class WalletService {
    static let shared = WalletService()

    private(set) var publicKey: String?
    private(set) var isCreating = false

    private let privy: (any Privy)?

    private init() {
        let bundle = Bundle.main
        guard
            let appId = bundle.object(forInfoDictionaryKey: "PrivyAppID") as? String,
            let clientId = bundle.object(forInfoDictionaryKey: "PrivyAppClientID") as? String,
            !appId.isEmpty, !clientId.isEmpty
        else {
            // Absent in builds that do not use the vault. Every call then fails
            // with .notConfigured rather than crashing at launch.
            privy = nil
            return
        }
        // The user has already signed in with Google or Apple, so they are not
        // asked to authenticate again. Privy takes a short-lived RS256 token
        // from our server and verifies it against our JWKS endpoint.
        privy = PrivySdk.initialize(
            config: PrivyConfig(
                appId: appId,
                appClientId: clientId,
                customAuthConfig: PrivyLoginWithCustomAuthConfig {
                    try await WalletService.walletToken()
                }
            )
        )
    }

    /// Fetches the token Privy exchanges for a wallet session.
    ///
    /// Nonisolated and static because Privy calls it from its own context
    /// whenever it needs to refresh, which can be long after sign-in.
    private nonisolated static func walletToken() async throws -> String? {
        try await APIClient.shared.getWalletToken(.init()).ok.body.json.token
    }

    /// Establishes the Privy session, reusing one if it is already live.
    ///
    /// Separate from `ensureWallet` because the session is what fails when the
    /// server is unreachable, and distinguishing that from a wallet that has
    /// not been created yet matters when reading a bug report.
    private func authenticatedUser() async throws -> any PrivyUser {
        guard let privy else { throw WalletError.notConfigured }

        if let user = await privy.getUser() { return user }

        do {
            return try await privy.customJwt.loginWithCustomAccessToken()
        } catch {
            throw WalletError.sessionFailed(error.localizedDescription)
        }
    }

    var isReady: Bool { publicKey != nil }
    var isConfigured: Bool { privy != nil }

    /// Returns the wallet address, creating the wallet on first use.
    @discardableResult
    func ensureWallet() async throws -> String {
        if let publicKey { return publicKey }
        let user = try await authenticatedUser()

        if let existing = user.embeddedSolanaWallets.first {
            publicKey = existing.address
            return existing.address
        }

        isCreating = true
        defer { isCreating = false }

        do {
            let wallet = try await user.createSolanaWallet()
            publicKey = wallet.address
            return wallet.address
        } catch {
            throw WalletError.creationFailed(error.localizedDescription)
        }
    }

    /// Creates the Privy wallet if needed and registers it on the server.
    ///
    /// Call after sign-in (background) so Deposit / personal wallet work
    /// without visiting a trip vault first. Idempotent.
    @discardableResult
    func ensureLinked() async throws -> String {
        guard isConfigured else { throw WalletError.notConfigured }
        let address = try await ensureWallet()
        _ = try await APIClient.shared.linkWallet(
            .init(body: .json(.init(publicKey: address)))
        ).created
        return address
    }

    /// Clears local wallet state and the Privy session (account switch / logout).
    func reset() async {
        publicKey = nil
        guard let privy else { return }
        if let user = await privy.getUser() {
            await user.logout()
        }
    }

    /// Signs a server-built transaction and returns it fully signed, base64
    /// encoded, ready to POST back unchanged.
    ///
    /// The caller must have run `TransactionVerifier.verify` first. This method
    /// deliberately does not verify, so the check cannot be skipped by passing
    /// different arguments here than were checked.
    func sign(base64Tx: String) async throws -> String {
        let user = try await authenticatedUser()
        guard let wallet = user.embeddedSolanaWallets.first else {
            throw WalletError.notAuthenticated
        }
        guard let transaction = Data(base64Encoded: base64Tx) else {
            throw WalletError.malformedTransaction
        }

        do {
            // signTransaction, never signMessage. signMessage signs the bytes it
            // is given verbatim, so handing it a serialised transaction yields a
            // signature covering the 65-byte signature prefix too, which the
            // network rejects. signTransaction signs the message portion and
            // splices the signature back in at the right offset. See
            // docs/superpowers/notes/2026-07-26-privy-solana-spike.md.
            return try await wallet.provider.signTransaction(transaction: transaction)
        } catch {
            throw WalletError.signingFailed(error.localizedDescription)
        }
    }
}
