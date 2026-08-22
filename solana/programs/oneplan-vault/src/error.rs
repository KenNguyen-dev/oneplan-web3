use anchor_lang::prelude::*;

#[error_code]
pub enum VaultError {
    #[msg("Vault is not accepting operations")]
    VaultNotActive,
    #[msg("Vault must be in the Settling state")]
    VaultNotSettling,
    #[msg("Vault must be Closed and empty")]
    VaultNotClosable,
    #[msg("Member is not active")]
    MemberNotActive,
    #[msg("Member not found in this vault")]
    MemberNotFound,
    #[msg("Vault already has the maximum number of members")]
    VaultFull,
    #[msg("Member is already in this vault")]
    MemberAlreadyExists,
    #[msg("Amount exceeds the single-signature threshold")]
    AboveThreshold,
    #[msg("Amount is within the threshold; use spend instead")]
    BelowThreshold,
    #[msg("Daily spend limit exceeded")]
    DailyLimitExceeded,
    #[msg("Insufficient vault balance")]
    InsufficientFunds,
    #[msg("Proposal has expired")]
    ProposalExpired,
    #[msg("Proposal has already been executed")]
    AlreadyExecuted,
    #[msg("This member has already approved the proposal")]
    DuplicateApproval,
    #[msg("This trip restricts approvals to its host and co-host")]
    NotAnApprover,
    #[msg("Too many payouts in one settlement")]
    TooManyPayouts,
    #[msg("Settlement payouts exceed the vault balance")]
    PayoutsExceedBalance,
    #[msg("Accounting invariant violated")]
    InvariantViolated,
    #[msg("Arithmetic overflow")]
    Overflow,
    #[msg("No active spend proposal on this vault")]
    NoActiveSpend,
    #[msg("Another spend proposal is already pending")]
    SpendSlotOccupied,
    #[msg("Only the proposer, host, or co-host may cancel")]
    NotAllowedToCancel,
    #[msg("Settlement is already open on this vault")]
    SettlementAlreadyOpen,
    #[msg("Deposit amount too small after fee")]
    DepositTooSmall,
}
