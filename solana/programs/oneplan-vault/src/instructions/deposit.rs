use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};

use crate::constants::{DEPOSIT_FEE_BPS, VAULT_SEED};
use crate::error::VaultError;
use crate::invariant::assert_invariant;
use crate::state::{TripVault, VaultStatus};

#[derive(Accounts)]
pub struct Deposit<'info> {
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

    /// OnePlan treasury USDC ATA — receives the deposit skim.
    #[account(mut, constraint = treasury_ata.mint == usdc_mint.key())]
    pub treasury_ata: Account<'info, TokenAccount>,

    #[account(mut, constraint = owner_ata.mint == usdc_mint.key())]
    pub owner_ata: Account<'info, TokenAccount>,

    pub owner: Signer<'info>,

    #[account(address = vault.usdc_mint)]
    pub usdc_mint: Account<'info, Mint>,

    pub token_program: Program<'info, Token>,
}

pub fn handle_deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
    require!(
        ctx.accounts.vault.status == VaultStatus::Active,
        VaultError::VaultNotActive
    );

    // Confirm the signer is an active member before moving tokens.
    ctx.accounts.vault.require_active_member(&ctx.accounts.owner.key())?;

    let fee = amount
        .checked_mul(DEPOSIT_FEE_BPS)
        .ok_or(VaultError::Overflow)?
        .checked_div(10_000)
        .ok_or(VaultError::Overflow)?;
    let net = amount.checked_sub(fee).ok_or(VaultError::Overflow)?;
    require!(net > 0, VaultError::DepositTooSmall);

    // Net → vault.
    token::transfer(
        CpiContext::new(
            ctx.accounts.token_program.key(),
            Transfer {
                from: ctx.accounts.owner_ata.to_account_info(),
                to: ctx.accounts.vault_ata.to_account_info(),
                authority: ctx.accounts.owner.to_account_info(),
            },
        ),
        net,
    )?;

    // Skim → treasury (skip CPI when fee rounds to zero).
    if fee > 0 {
        token::transfer(
            CpiContext::new(
                ctx.accounts.token_program.key(),
                Transfer {
                    from: ctx.accounts.owner_ata.to_account_info(),
                    to: ctx.accounts.treasury_ata.to_account_info(),
                    authority: ctx.accounts.owner.to_account_info(),
                },
            ),
            fee,
        )?;
    }

    let owner = ctx.accounts.owner.key();
    let member = ctx.accounts.vault.require_active_member_mut(&owner)?;
    member.deposited = member
        .deposited
        .checked_add(net)
        .ok_or(VaultError::Overflow)?;

    let vault = &mut ctx.accounts.vault;
    vault.total_deposited = vault
        .total_deposited
        .checked_add(net)
        .ok_or(VaultError::Overflow)?;

    ctx.accounts.vault_ata.reload()?;
    assert_invariant(&ctx.accounts.vault, ctx.accounts.vault_ata.amount)?;

    Ok(())
}
