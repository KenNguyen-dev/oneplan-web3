use anchor_lang::prelude::*;

use crate::constants::{MAX_MEMBERS, MAX_PAYOUTS, REQUIRED_APPROVALS, ROLE_APPROVER};
use crate::error::VaultError;

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Debug, InitSpace)]
pub enum VaultStatus {
    Active,
    Settling,
    Closed,
}

/// One seat in the vault's member table. No separate PDA.
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Debug, InitSpace, Default)]
pub struct MemberRecord {
    pub owner: Pubkey,
    pub deposited: u64,
    pub refunded: u64,
    pub active: bool,
    /// Zero for an ordinary member; `ROLE_APPROVER` for HOST / CO_HOST.
    pub role: u8,
}

/// Above-threshold spend waiting for a second approval. At most one at a time.
#[derive(AnchorSerialize, AnchorDeserialize, Clone, InitSpace, Default)]
pub struct ActiveSpend {
    pub proposer: Pubkey,
    pub recipient: Pubkey,
    pub amount: u64,
    #[max_len(REQUIRED_APPROVALS)]
    pub approvals: Vec<Pubkey>,
    pub expires_at: i64,
}

/// Settlement batch slot on the vault account.
///
/// Kept for PDA layout compatibility with vaults created before server-only
/// `execute_settlement`. New flow never opens this; fields stay default/cleared.
#[derive(AnchorSerialize, AnchorDeserialize, Clone, InitSpace, Default)]
pub struct ActiveSettlement {
    #[max_len(MAX_PAYOUTS)]
    pub payouts: Vec<Payout>,
    #[max_len(REQUIRED_APPROVALS)]
    pub approvals: Vec<Pubkey>,
    pub expires_at: i64,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, InitSpace, Default)]
pub struct Payout {
    pub member: Pubkey,
    pub amount: u64,
}

#[account]
#[derive(InitSpace)]
pub struct TripVault {
    /// OnePlan trip id, also the PDA seed.
    pub trip_id: u64,
    /// Trip creator. May add and deactivate members.
    pub authority: Pubkey,
    /// Backend signer. May execute settlement and revert spends.
    pub server: Pubkey,
    pub usdc_mint: Pubkey,
    /// Spends at or below this amount need one signature. Micro-USDC.
    pub threshold: u64,
    /// Rolling 24h ceiling for single-signature spends. Micro-USDC.
    pub daily_limit: u64,
    /// Unix timestamp at which the current daily window opened.
    pub day_start: i64,
    pub spent_today: u64,
    pub member_count: u16,
    /// Members with `ROLE_APPROVER`. Restriction kicks in at
    /// `MIN_APPROVERS_TO_RESTRICT`.
    pub approver_count: u16,
    pub total_deposited: u64,
    pub total_spent: u64,
    pub status: VaultStatus,
    pub bump: u8,
    #[max_len(MAX_MEMBERS)]
    pub members: Vec<MemberRecord>,
    pub has_active_spend: bool,
    pub active_spend: ActiveSpend,
    pub has_settlement: bool,
    pub settlement: ActiveSettlement,
}

impl TripVault {
    pub fn find_member_index(&self, owner: &Pubkey) -> Option<usize> {
        self.members.iter().position(|m| m.owner == *owner)
    }

    pub fn require_active_member(&self, owner: &Pubkey) -> Result<&MemberRecord> {
        let m = self
            .members
            .iter()
            .find(|m| m.owner == *owner)
            .ok_or(VaultError::MemberNotFound)?;
        require!(m.active, VaultError::MemberNotActive);
        Ok(m)
    }

    pub fn require_active_member_mut(&mut self, owner: &Pubkey) -> Result<&mut MemberRecord> {
        let idx = self
            .find_member_index(owner)
            .ok_or(VaultError::MemberNotFound)?;
        require!(self.members[idx].active, VaultError::MemberNotActive);
        Ok(&mut self.members[idx])
    }

    pub fn is_approver(&self, owner: &Pubkey) -> bool {
        self.members
            .iter()
            .any(|m| m.owner == *owner && m.active && m.role == ROLE_APPROVER)
    }

    pub fn clear_active_spend(&mut self) {
        self.has_active_spend = false;
        self.active_spend = ActiveSpend::default();
    }

    pub fn clear_settlement(&mut self) {
        self.has_settlement = false;
        self.settlement = ActiveSettlement::default();
    }
}
