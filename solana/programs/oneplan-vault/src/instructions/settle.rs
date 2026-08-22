use anchor_lang::prelude::*;
use anchor_spl::token::{self, CloseAccount, Mint, Token, TokenAccount, Transfer};

use crate::constants::{MAX_PAYOUTS, ROLE_APPROVER, VAULT_SEED};
use crate::error::VaultError;
use crate::invariant::assert_invariant;
use crate::state::{Payout, TripVault, VaultStatus};

/// Server-authority settlement: pays out and closes in one instruction.
///
/// Called after off-chain end-trip consensus. Members do not co-sign.
/// `remaining_accounts` are recipient ATAs in payout order.
#[derive(Accounts)]
pub struct ExecuteSettlement<'info> {
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

    pub server: Signer<'info>,

    #[account(address = vault.usdc_mint)]
    pub usdc_mint: Account<'info, Mint>,

    pub token_program: Program<'info, Token>,
}

pub fn handle_execute_settlement<'info>(
    ctx: Context<'info, ExecuteSettlement<'info>>,
    payouts: Vec<Payout>,
) -> Result<()> {
    require!(
        ctx.accounts.vault.status == VaultStatus::Active,
        VaultError::VaultNotActive
    );
    require!(
        !ctx.accounts.vault.has_settlement,
        VaultError::SettlementAlreadyOpen
    );
    require!(payouts.len() <= MAX_PAYOUTS, VaultError::TooManyPayouts);

    let mut total: u64 = 0;
    for p in payouts.iter() {
        total = total.checked_add(p.amount).ok_or(VaultError::Overflow)?;
    }
    require!(
        total <= ctx.accounts.vault_ata.amount,
        VaultError::PayoutsExceedBalance
    );

    ctx.accounts.vault.clear_active_spend();

    execute_payouts(
        &ctx.accounts.vault,
        &ctx.accounts.vault_ata,
        &ctx.accounts.usdc_mint,
        &ctx.accounts.token_program,
        ctx.remaining_accounts,
        &payouts,
    )?;

    let vault = &mut ctx.accounts.vault;
    vault.total_spent = vault
        .total_spent
        .checked_add(total)
        .ok_or(VaultError::Overflow)?;
    vault.status = VaultStatus::Closed;
    vault.clear_settlement();

    ctx.accounts.vault_ata.reload()?;
    assert_invariant(&ctx.accounts.vault, ctx.accounts.vault_ata.amount)?;

    Ok(())
}

/// Mid-trip leave: pay one active member from the vault and deactivate them.
/// Vault stays Active (unlike `execute_settlement`).
#[derive(Accounts)]
pub struct PayoutLeave<'info> {
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

    /// CHECK: recipient wallet; must match an active vault member.
    pub member: UncheckedAccount<'info>,

    #[account(
        mut,
        associated_token::mint = usdc_mint,
        associated_token::authority = member
    )]
    pub member_ata: Account<'info, TokenAccount>,

    pub server: Signer<'info>,

    #[account(address = vault.usdc_mint)]
    pub usdc_mint: Account<'info, Mint>,

    pub token_program: Program<'info, Token>,
}

pub fn handle_payout_leave(ctx: Context<PayoutLeave>, amount: u64) -> Result<()> {
    require!(
        ctx.accounts.vault.status == VaultStatus::Active,
        VaultError::VaultNotActive
    );
    require!(amount > 0, VaultError::DepositTooSmall);
    require!(
        amount <= ctx.accounts.vault_ata.amount,
        VaultError::PayoutsExceedBalance
    );

    let member_key = ctx.accounts.member.key();
    {
        let vault = &ctx.accounts.vault;
        let _ = vault.require_active_member(&member_key)?;
    }

    let trip_id_bytes = ctx.accounts.vault.trip_id.to_le_bytes();
    let bump = ctx.accounts.vault.bump;
    let seeds: &[&[u8]] = &[VAULT_SEED, &trip_id_bytes, &[bump]];

    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.key(),
            Transfer {
                from: ctx.accounts.vault_ata.to_account_info(),
                to: ctx.accounts.member_ata.to_account_info(),
                authority: ctx.accounts.vault.to_account_info(),
            },
            &[seeds],
        ),
        amount,
    )?;

    let vault = &mut ctx.accounts.vault;
    let idx = vault
        .find_member_index(&member_key)
        .ok_or(VaultError::MemberNotFound)?;

    vault.members[idx].refunded = vault.members[idx]
        .refunded
        .checked_add(amount)
        .ok_or(VaultError::Overflow)?;

    if vault.members[idx].active {
        let was_approver = vault.members[idx].role == ROLE_APPROVER;
        vault.members[idx].active = false;
        vault.members[idx].role = 0;
        if was_approver {
            vault.approver_count = vault.approver_count.saturating_sub(1);
        }
        vault.member_count = vault.member_count.saturating_sub(1);
    }

    vault.total_spent = vault
        .total_spent
        .checked_add(amount)
        .ok_or(VaultError::Overflow)?;

    ctx.accounts.vault_ata.reload()?;
    assert_invariant(&ctx.accounts.vault, ctx.accounts.vault_ata.amount)?;

    Ok(())
}

fn execute_payouts<'info>(
    vault: &Account<'info, TripVault>,
    vault_ata: &Account<'info, TokenAccount>,
    usdc_mint: &Account<'info, Mint>,
    token_program: &Program<'info, Token>,
    remaining_accounts: &'info [AccountInfo<'info>],
    payouts: &[Payout],
) -> Result<()> {
    require!(
        remaining_accounts.len() == payouts.len(),
        VaultError::InvariantViolated
    );

    let trip_id_bytes = vault.trip_id.to_le_bytes();
    let bump = vault.bump;
    let seeds: &[&[u8]] = &[VAULT_SEED, &trip_id_bytes, &[bump]];

    for (i, payout) in payouts.iter().enumerate() {
        let dest = &remaining_accounts[i];
        let dest_data = Account::<TokenAccount>::try_from(dest)?;
        require!(
            dest_data.owner == payout.member && dest_data.mint == usdc_mint.key(),
            VaultError::InvariantViolated
        );

        token::transfer(
            CpiContext::new_with_signer(
                token_program.key(),
                Transfer {
                    from: vault_ata.to_account_info(),
                    to: dest.to_account_info(),
                    authority: vault.to_account_info(),
                },
                &[seeds],
            ),
            payout.amount,
        )?;
    }

    Ok(())
}

#[derive(Accounts)]
pub struct CloseVault<'info> {
    #[account(
        mut,
        seeds = [VAULT_SEED, &vault.trip_id.to_le_bytes()],
        bump = vault.bump,
        has_one = server,
        close = server
    )]
    pub vault: Account<'info, TripVault>,

    #[account(
        mut,
        associated_token::mint = vault.usdc_mint,
        associated_token::authority = vault
    )]
    pub vault_ata: Account<'info, TokenAccount>,

    /// Fee payer that funded `init_vault`; receives PDA + ATA rent back.
    #[account(mut)]
    pub server: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

/// Closes the empty vault ATA then the TripVault PDA. Rent for both returns
/// to `server`, which paid for them at init. Call after settlement has set
/// status to Closed and emptied the ATA — the app/server does this behind
/// settle, not as a separate user action.
pub fn handle_close_vault(ctx: Context<CloseVault>) -> Result<()> {
    require!(
        ctx.accounts.vault.status == VaultStatus::Closed && ctx.accounts.vault_ata.amount == 0,
        VaultError::VaultNotClosable
    );

    let trip_id_bytes = ctx.accounts.vault.trip_id.to_le_bytes();
    let bump = ctx.accounts.vault.bump;
    let seeds: &[&[u8]] = &[VAULT_SEED, &trip_id_bytes, &[bump]];

    token::close_account(CpiContext::new_with_signer(
        ctx.accounts.token_program.key(),
        CloseAccount {
            account: ctx.accounts.vault_ata.to_account_info(),
            destination: ctx.accounts.server.to_account_info(),
            authority: ctx.accounts.vault.to_account_info(),
        },
        &[seeds],
    ))?;

    Ok(())
}
