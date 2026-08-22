import Foundation

/// Trip-wallet welcome presentation — once per signed-in user.
///
/// Persists a seen flag in UserDefaults keyed by user id. Continue, Close, and
/// Add money all call `complete`, so any dismiss counts as seen.
@MainActor
@Observable
final class TripWalletWelcomeManager {
    /// True while the welcome sheet is up.
    var isPresented = false

    private static let seenKeyPrefix = "tripWalletWelcome.seen."

    func presentIfNeeded(userId: String?, walletConfigured: Bool) {
        guard !isPresented else { return }
        guard let userId, !userId.isEmpty else { return }
        // Wallet setup runs inside the sheet; only require a logged-in user.
        _ = walletConfigured
        guard !hasSeen(userId: userId) else { return }
        isPresented = true
    }

    /// Dismiss and remember for this user so it does not show again.
    func complete(userId: String?) {
        if let userId, !userId.isEmpty {
            UserDefaults.standard.set(true, forKey: Self.seenKey(for: userId))
        }
        isPresented = false
    }

    private func hasSeen(userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: Self.seenKey(for: userId))
    }

    private static func seenKey(for userId: String) -> String {
        seenKeyPrefix + userId
    }
}
