use anchor_lang::prelude::*;
use anchor_spl::associated_token::AssociatedToken;
use anchor_spl::token::{Mint, Token, TokenAccount};

use crate::constants::VAULT_SEED;
use crate::state::{ActiveSettlement, ActiveSpend, TripVault, VaultStatus};

#[derive(Accounts)]
#[instruction(trip_id: u64)]
pub struct InitVault<'info> {
    #[account(
        init,
        payer = server,
        space = 8 + TripVault::INIT_SPACE,
        seeds = [VAULT_SEED, &trip_id.to_le_bytes()],
        bump
    )]
    pub vault: Account<'info, TripVault>,

    #[account(
        init,
        payer = server,
        associated_token::mint = usdc_mint,
        associated_token::authority = vault
    )]
    pub vault_ata: Account<'info, TokenAccount>,

    pub usdc_mint: Account<'info, Mint>,

    /// Trip creator. Recorded as the authority that manages members.
    pub authority: Signer<'info>,

    /// Backend signer and fee payer. Recorded as the server authority.
    #[account(mut)]
    pub server: Signer<'info>,

    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

pub fn handle_init_vault(
    ctx: Context<InitVault>,
    trip_id: u64,
    threshold: u64,
    daily_limit: u64,
) -> Result<()> {
    let clock = Clock::get()?;
    let vault = &mut ctx.accounts.vault;

    vault.trip_id = trip_id;
    vault.authority = ctx.accounts.authority.key();
    vault.server = ctx.accounts.server.key();
    vault.usdc_mint = ctx.accounts.usdc_mint.key();
    vault.threshold = threshold;
    vault.daily_limit = daily_limit;
    vault.day_start = clock.unix_timestamp;
    vault.spent_today = 0;
    vault.member_count = 0;
    vault.approver_count = 0;
    vault.total_deposited = 0;
    vault.total_spent = 0;
    vault.status = VaultStatus::Active;
    vault.bump = ctx.bumps.vault;
    vault.members = Vec::new();
    vault.has_active_spend = false;
    vault.active_spend = ActiveSpend::default();
    vault.has_settlement = false;
    vault.settlement = ActiveSettlement::default();

    Ok(())
}
