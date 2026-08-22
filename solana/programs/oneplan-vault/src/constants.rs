use anchor_lang::prelude::*;

#[constant]
pub const VAULT_SEED: &[u8] = b"vault";

/// Proposals expire 24 hours after creation.
#[constant]
pub const PROPOSAL_TTL_SECONDS: i64 = 86_400;

/// Length of the rolling window for the daily spend ceiling.
#[constant]
pub const DAY_SECONDS: i64 = 86_400;

/// Distinct member approvals required to execute any proposal.
pub const REQUIRED_APPROVALS: usize = 2;

/// Hard cap on trip vault members (on-chain array / payout bound).
pub const MAX_MEMBERS: usize = 12;

/// Upper bound on settlement payouts (= max members).
pub const MAX_PAYOUTS: usize = MAX_MEMBERS;

/// Deposit skim in basis points (10 = 0.1%).
#[constant]
pub const DEPOSIT_FEE_BPS: u64 = 10;

/// Approvals are restricted to designated approvers only once a trip has at
/// least this many. Below it any active member may approve, which is what stops
/// a trip whose sole approver raised the payment from deadlocking.
#[constant]
pub const MIN_APPROVERS_TO_RESTRICT: u16 = 2;

/// `MemberRecord::role` for someone who may approve (HOST / CO_HOST in the app).
#[constant]
pub const ROLE_APPROVER: u8 = 1;
