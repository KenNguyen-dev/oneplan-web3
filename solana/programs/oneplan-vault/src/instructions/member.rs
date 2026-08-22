use anchor_lang::prelude::*;

use crate::constants::{MAX_MEMBERS, ROLE_APPROVER, VAULT_SEED};
use crate::error::VaultError;
use crate::state::{MemberRecord, TripVault, VaultStatus};

#[derive(Accounts)]
pub struct AddMember<'info> {
    #[account(
        mut,
        seeds = [VAULT_SEED, &vault.trip_id.to_le_bytes()],
        bump = vault.bump,
        has_one = authority
    )]
    pub vault: Account<'info, TripVault>,

    /// CHECK: only the pubkey is recorded; a member never signs to be added.
    pub owner: UncheckedAccount<'info>,

    pub authority: Signer<'info>,
}

pub fn handle_add_member(ctx: Context<AddMember>) -> Result<()> {
    require!(
        ctx.accounts.vault.status == VaultStatus::Active,
        VaultError::VaultNotActive
    );

    let owner = ctx.accounts.owner.key();
    let vault = &mut ctx.accounts.vault;

    if let Some(existing) = vault.members.iter_mut().find(|m| m.owner == owner) {
        require!(!existing.active, VaultError::MemberAlreadyExists);
        // Re-activate a previously deactivated seat (keeps deposit history).
        existing.active = true;
        vault.member_count = vault
            .member_count
            .checked_add(1)
            .ok_or(VaultError::Overflow)?;
        return Ok(());
    }

    require!(
        vault.members.len() < MAX_MEMBERS,
        VaultError::VaultFull
    );

    vault.members.push(MemberRecord {
        owner,
        deposited: 0,
        refunded: 0,
        active: true,
        role: 0,
    });
    vault.member_count = vault
        .member_count
        .checked_add(1)
        .ok_or(VaultError::Overflow)?;

    Ok(())
}

#[derive(Accounts)]
pub struct DeactivateMember<'info> {
    #[account(
        mut,
        seeds = [VAULT_SEED, &vault.trip_id.to_le_bytes()],
        bump = vault.bump,
        has_one = authority
    )]
    pub vault: Account<'info, TripVault>,

    /// CHECK: identified by pubkey; must already be in the vault table.
    pub owner: UncheckedAccount<'info>,

    pub authority: Signer<'info>,
}

pub fn handle_deactivate_member(ctx: Context<DeactivateMember>) -> Result<()> {
    let owner = ctx.accounts.owner.key();
    let vault = &mut ctx.accounts.vault;
    let idx = vault
        .find_member_index(&owner)
        .ok_or(VaultError::MemberNotFound)?;

    if vault.members[idx].active {
        let was_approver = vault.members[idx].role == ROLE_APPROVER;
        vault.members[idx].active = false;
        vault.members[idx].role = 0;
        if was_approver {
            vault.approver_count = vault.approver_count.saturating_sub(1);
        }
        vault.member_count = vault.member_count.saturating_sub(1);
    }
    Ok(())
}

#[derive(Accounts)]
pub struct SetMemberRole<'info> {
    #[account(
        mut,
        seeds = [VAULT_SEED, &vault.trip_id.to_le_bytes()],
        bump = vault.bump,
        has_one = server
    )]
    pub vault: Account<'info, TripVault>,

    /// CHECK: identified by pubkey; must already be in the vault table.
    pub owner: UncheckedAccount<'info>,

    /// The backend, not the trip's authority. Who may appoint a co-host is a
    /// trip decision the app owns; the chain only records the answer.
    pub server: Signer<'info>,
}

pub fn handle_set_member_role(ctx: Context<SetMemberRole>, role: u8) -> Result<()> {
    let owner = ctx.accounts.owner.key();
    let vault = &mut ctx.accounts.vault;
    let member = vault
        .members
        .iter_mut()
        .find(|m| m.owner == owner)
        .ok_or(VaultError::MemberNotFound)?;

    let was_approver = member.role == ROLE_APPROVER;
    let is_approver = role == ROLE_APPROVER;
    member.role = role;

    if is_approver && !was_approver {
        vault.approver_count = vault
            .approver_count
            .checked_add(1)
            .ok_or(VaultError::Overflow)?;
    } else if !is_approver && was_approver {
        vault.approver_count = vault.approver_count.saturating_sub(1);
    }

    Ok(())
}
