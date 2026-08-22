use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};

use crate::constants::{DAY_SECONDS, VAULT_SEED};
use crate::error::VaultError;
use crate::invariant::assert_invariant;
use crate::state::{TripVault, VaultStatus};

/// Moves `amount` out of the vault, updating totals and, when
/// `count_towards_daily` is set, the rolling daily window.
/// Shared by `spend` and by proposal execution in `proposal.rs`.
pub fn debit_vault<'info>(
    vault: &mut Account<'info, TripVault>,
    vault_ata: &Account<'info, TokenAccount>,
    recipient_ata: &Account<'info, TokenAccount>,
    token_program: &Program<'info, Token>,
    amount: u64,
    count_towards_daily: bool,
) -> Result<()> {
    require!(vault_ata.amount >= amount, VaultError::InsufficientFunds);

    if count_towards_daily {
        let now = Clock::get()?.unix_timestamp;
        if now.saturating_sub(vault.day_start) >= DAY_SECONDS {
            vault.day_start = now;
            vault.spent_today = 0;
        }
        let after = vault
            .spent_today
            .checked_add(amount)
            .ok_or(VaultError::Overflow)?;
        require!(after <= vault.daily_limit, VaultError::DailyLimitExceeded);
        vault.spent_today = after;
    }

    let trip_id_bytes = vault.trip_id.to_le_bytes();
    let seeds: &[&[u8]] = &[VAULT_SEED, &trip_id_bytes, &[vault.bump]];

    token::transfer(
        CpiContext::new_with_signer(
            token_program.key(),
            Transfer {
                from: vault_ata.to_account_info(),
                to: recipient_ata.to_account_info(),
                authority: vault.to_account_info(),
            },
            &[seeds],
        ),
        amount,
    )?;

    vault.total_spent = vault
        .total_spent
        .checked_add(amount)
        .ok_or(VaultError::Overflow)?;

    Ok(())
}

#[derive(Accounts)]
pub struct Spend<'info> {
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

    #[account(mut, constraint = recipient_ata.mint == usdc_mint.key())]
    pub recipient_ata: Account<'info, TokenAccount>,

    #[account(address = vault.usdc_mint)]
    pub usdc_mint: Account<'info, Mint>,

    pub token_program: Program<'info, Token>,
}

pub fn handle_spend(ctx: Context<Spend>, amount: u64) -> Result<()> {
    require!(
        ctx.accounts.vault.status == VaultStatus::Active,
        VaultError::VaultNotActive
    );
    require!(
        amount <= ctx.accounts.vault.threshold,
        VaultError::AboveThreshold
    );

    // Small spends stay allowed even while an above-threshold proposal is pending.
    ctx.accounts
        .vault
        .require_active_member(&ctx.accounts.signer.key())?;

    debit_vault(
        &mut ctx.accounts.vault,
        &ctx.accounts.vault_ata,
        &ctx.accounts.recipient_ata,
        &ctx.accounts.token_program,
        amount,
        true,
    )?;

    ctx.accounts.vault_ata.reload()?;
    assert_invariant(&ctx.accounts.vault, ctx.accounts.vault_ata.amount)?;
    Ok(())
}

#[derive(Accounts)]
pub struct RevertSpend<'info> {
    #[account(
        mut,
        seeds = [VAULT_SEED, &vault.trip_id.to_le_bytes()],
        bump = vault.bump,
        has_one = server
    )]
    pub vault: Account<'info, TripVault>,

    #[account(
        mut,
        associated_token::mint = usdc_mint,
        associated_token::authority = vault
    )]
    pub vault_ata: Account<'info, TokenAccount>,

    #[account(mut, constraint = receiver_ata.mint == usdc_mint.key())]
    pub receiver_ata: Account<'info, TokenAccount>,

    /// Owner of `receiver_ata`, signing the transfer back into the vault.
    pub receiver: Signer<'info>,

    pub server: Signer<'info>,

    #[account(address = vault.usdc_mint)]
    pub usdc_mint: Account<'info, Mint>,

    pub token_program: Program<'info, Token>,
}

pub fn handle_revert_spend(ctx: Context<RevertSpend>, amount: u64) -> Result<()> {
    token::transfer(
        CpiContext::new(
            ctx.accounts.token_program.key(),
            Transfer {
                from: ctx.accounts.receiver_ata.to_account_info(),
                to: ctx.accounts.vault_ata.to_account_info(),
                authority: ctx.accounts.receiver.to_account_info(),
            },
        ),
        amount,
    )?;

    let vault = &mut ctx.accounts.vault;
    vault.total_spent = vault
        .total_spent
        .checked_sub(amount)
        .ok_or(VaultError::Overflow)?;
    vault.spent_today = vault.spent_today.saturating_sub(amount);

    ctx.accounts.vault_ata.reload()?;
    assert_invariant(&ctx.accounts.vault, ctx.accounts.vault_ata.amount)?;
    Ok(())
}
