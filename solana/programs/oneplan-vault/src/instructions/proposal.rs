use anchor_lang::prelude::*;
use anchor_spl::token::{Mint, Token, TokenAccount};

use crate::constants::{
    MIN_APPROVERS_TO_RESTRICT, PROPOSAL_TTL_SECONDS, REQUIRED_APPROVALS, ROLE_APPROVER, VAULT_SEED,
};
use crate::error::VaultError;
use crate::instructions::spend::debit_vault;
use crate::invariant::assert_invariant;
use crate::state::{ActiveSpend, TripVault, VaultStatus};

#[derive(Accounts)]
pub struct ProposeSpend<'info> {
    #[account(
        mut,
        seeds = [VAULT_SEED, &vault.trip_id.to_le_bytes()],
        bump = vault.bump
    )]
    pub vault: Account<'info, TripVault>,

    pub signer: Signer<'info>,

    pub recipient_ata: Account<'info, TokenAccount>,
}

pub fn handle_propose_spend(ctx: Context<ProposeSpend>, amount: u64) -> Result<()> {
    require!(
        ctx.accounts.vault.status == VaultStatus::Active,
        VaultError::VaultNotActive
    );
    require!(
        amount > ctx.accounts.vault.threshold,
        VaultError::BelowThreshold
    );

    let signer = ctx.accounts.signer.key();
    ctx.accounts.vault.require_active_member(&signer)?;

    let now = Clock::get()?.unix_timestamp;
    let vault = &mut ctx.accounts.vault;

    if vault.has_active_spend {
        let expired = now > vault.active_spend.expires_at;
        let same_proposer = vault.active_spend.proposer == signer;
        // HOST / CO_HOST (approver bit) may retire someone else's pending spend
        // the same way the original proposer can — one active slot, last write wins.
        let is_host = vault.is_approver(&signer);
        require!(
            expired || same_proposer || is_host,
            VaultError::SpendSlotOccupied
        );
        vault.clear_active_spend();
    }

    vault.has_active_spend = true;
    vault.active_spend = ActiveSpend {
        proposer: signer,
        recipient: ctx.accounts.recipient_ata.key(),
        amount,
        approvals: vec![signer],
        expires_at: now + PROPOSAL_TTL_SECONDS,
    };

    Ok(())
}

#[derive(Accounts)]
pub struct ApproveSpend<'info> {
    #[account(
        mut,
        seeds = [VAULT_SEED, &vault.trip_id.to_le_bytes()],
        bump = vault.bump
    )]
    pub vault: Account<'info, TripVault>,

    #[account(
        mut,
        associated_token::mint = usdc_mint,
        associated_token::authority = vault
    )]
    pub vault_ata: Account<'info, TokenAccount>,

    pub signer: Signer<'info>,

    #[account(mut)]
    pub recipient_ata: Account<'info, TokenAccount>,

    #[account(address = vault.usdc_mint)]
    pub usdc_mint: Account<'info, Mint>,

    pub token_program: Program<'info, Token>,
}

pub fn handle_approve_spend(ctx: Context<ApproveSpend>) -> Result<()> {
    require!(
        ctx.accounts.vault.has_active_spend,
        VaultError::NoActiveSpend
    );

    let now = Clock::get()?.unix_timestamp;
    require!(
        now <= ctx.accounts.vault.active_spend.expires_at,
        VaultError::ProposalExpired
    );
    require!(
        ctx.accounts.recipient_ata.key() == ctx.accounts.vault.active_spend.recipient,
        VaultError::InvariantViolated
    );

    let signer = ctx.accounts.signer.key();
    let member_role = ctx.accounts.vault.require_active_member(&signer)?.role;

    require!(
        !ctx.accounts.vault.active_spend.approvals.contains(&signer),
        VaultError::DuplicateApproval
    );

    if ctx.accounts.vault.approver_count >= MIN_APPROVERS_TO_RESTRICT {
        require!(member_role == ROLE_APPROVER, VaultError::NotAnApprover);
    }

    let amount = ctx.accounts.vault.active_spend.amount;
    ctx.accounts.vault.active_spend.approvals.push(signer);

    if ctx.accounts.vault.active_spend.approvals.len() >= REQUIRED_APPROVALS {
        debit_vault(
            &mut ctx.accounts.vault,
            &ctx.accounts.vault_ata,
            &ctx.accounts.recipient_ata,
            &ctx.accounts.token_program,
            amount,
            false,
        )?;
        ctx.accounts.vault.clear_active_spend();

        ctx.accounts.vault_ata.reload()?;
        assert_invariant(&ctx.accounts.vault, ctx.accounts.vault_ata.amount)?;
    }

    Ok(())
}

#[derive(Accounts)]
pub struct CancelSpend<'info> {
    #[account(
        mut,
        seeds = [VAULT_SEED, &vault.trip_id.to_le_bytes()],
        bump = vault.bump
    )]
    pub vault: Account<'info, TripVault>,

    pub signer: Signer<'info>,
}

pub fn handle_cancel_spend(ctx: Context<CancelSpend>) -> Result<()> {
    require!(
        ctx.accounts.vault.has_active_spend,
        VaultError::NoActiveSpend
    );

    let signer = ctx.accounts.signer.key();
    let is_proposer = ctx.accounts.vault.active_spend.proposer == signer;
    let is_host = ctx.accounts.vault.is_approver(&signer);
    require!(is_proposer || is_host, VaultError::NotAllowedToCancel);

    // Proposer may cancel without being looked up as a member; HOST/CO_HOST
    // must still be an active approver (checked via is_approver).
    if !is_proposer {
        ctx.accounts.vault.require_active_member(&signer)?;
    }

    ctx.accounts.vault.clear_active_spend();
    Ok(())
}
