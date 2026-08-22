import Foundation

/// Copy for “How your money is held” (full doc + short sheet).
///
/// Template content only — typography/layout will follow Figma in a later pass.
/// All user-facing strings go through `String(localized:)` so VI catalog applies.
enum HowMoneyIsHeldCopy {
    struct Section: Identifiable {
        let id: String
        let title: String?
        let paragraphs: [String]
        let bullets: [String]
    }

    /// Screen 1 — full disclosure (also what “See how…” opens).
    static var fullSections: [Section] {
        [
            Section(
                id: "wallet-yours",
                title: String(localized: "Your wallet is yours"),
                paragraphs: [
                    String(localized: "When you sign in, a wallet is created for your account through our wallet provider, Privy. It holds USDC, a dollar-backed stablecoin, on the Solana network."),
                    String(localized: "You do not need to install anything, and there is no seed phrase to write down or lose. Your access comes from the account you already sign in with."),
                ],
                bullets: []
            ),
            Section(
                id: "nothing-moves",
                title: String(localized: "Nothing moves without your approval"),
                paragraphs: [
                    String(localized: "Every payment out of your wallet needs you to approve it. That includes putting money into a trip fund."),
                ],
                bullets: []
            ),
            Section(
                id: "trip-fund",
                title: String(localized: "A trip fund belongs to the group, not to one friend"),
                paragraphs: [
                    String(localized: "Normally one person in a group pays for the hotel and then spends two weeks asking everyone else for money. A trip fund replaces that."),
                ],
                bullets: [
                    String(localized: "Every member sees the balance and every movement, at any time"),
                    String(localized: "Spending above the limit your group sets needs a second member to approve it before any money moves"),
                    String(localized: "At the end of the trip, one settlement pays everyone back at once, and every member can check the numbers themselves"),
                ]
            ),
            Section(
                id: "trust-line",
                title: nil,
                paragraphs: [
                    String(localized: "Nobody has to trust one friend with everyone's money."),
                ],
                bullets: []
            ),
            Section(
                id: "fees",
                title: String(localized: "We pay the network fees"),
                paragraphs: [
                    String(localized: "Sending anything on Solana costs a small network fee. We cover those, so you never need to hold SOL or think about it."),
                ],
                bullets: []
            ),
            Section(
                id: "can-cannot",
                title: String(localized: "What we can and cannot do"),
                paragraphs: [
                    String(localized: "We can: show your balance, prepare a payment for you to approve, and pay the network fees."),
                    String(localized: "We cannot: spend your money, move it out of your wallet, or approve a group payment on your behalf."),
                ],
                bullets: []
            ),
            Section(
                id: "what-can-go-wrong",
                title: String(localized: "What can go wrong, and what we do about it"),
                paragraphs: [
                    String(localized: "We would rather tell you this now than when it happens."),
                    String(localized: "You lose access to your sign-in account. Your wallet is tied to the account you sign in with. Losing that account means losing in-app access to the wallet. We do not currently offer a separate recovery method (no seed phrase in the app). Protect your Apple or Google account. Once we ship key export, you will be able to save your Solana private key and import it into another wallet (for example Phantom). If you have already exported that key, you can still reach your personal USDC even without OnePlan login. Export must happen before you lose access."),
                    String(localized: "You send USDC to a wrong address. Transfers on Solana cannot be reversed. We check the address format before sending and block addresses from other networks, but we cannot undo a transfer to a valid address that turns out to be the wrong person."),
                    String(localized: "A payment looks like it failed but went through. Confirming a payment and making it are two separate steps. If confirmation is slow, you may see a failure for a few minutes before the status corrects itself. Your money is not lost, and we reconcile against the network automatically."),
                    String(localized: "The stablecoin. USDC is issued by Circle and designed to hold a value of one US dollar. It is not issued by OnePlan and it is not a bank deposit. It is not insured by any government deposit scheme."),
                    String(localized: "A trip fund with no second approver. If your trip has fewer than two people who can approve, any member may approve a payment. Two-person approval only starts once your group has two approvers."),
                ],
                bullets: []
            ),
            Section(
                id: "faq",
                title: String(localized: "Questions we get asked"),
                paragraphs: [
                    String(localized: "Is this a bank account? No. It is not a bank account, not a savings product, and not insured by a deposit protection scheme. It is a place to hold trip money and move it between people."),
                    String(localized: "Do you earn interest on my balance? No. Your balance does not earn anything, and we do not lend it out or invest it."),
                    String(localized: "Can I take my money out at any time? Yes, to your own wallet address, subject to network confirmation. Money already inside a trip fund follows your group's approval rules."),
                    String(localized: "What happens if OnePlan shuts down? Your personal USDC sits in your Privy wallet on Solana. OnePlan does not hold it as a bank. If the app disappears, that balance stays on-chain; access is through Privy with the same sign-in, or through a private key you exported earlier into another Solana wallet. Money already inside a trip fund also remains on Solana in the group vault. Managing approvals and payouts today depends on OnePlan. Without the app, that path is not simple for most people — personal wallet funds are the part you can take with you most reliably."),
                    String(localized: "Who else can see my transactions? Members of a trip can see that trip's fund and its movements. Solana is a public network, so wallet activity is visible on it, though it is not labelled with your name by us."),
                ],
                bullets: []
            ),
        ]
    }
}
