use anchor_lang::prelude::*;

use crate::error::VaultError;
use crate::state::TripVault;

/// Asserts the core accounting identity:
/// `total_deposited - total_spent == vault_ata.amount`.
///
/// Call this at the end of every instruction that moves funds, passing the token
/// account balance re-read after the transfer.
pub fn assert_invariant(vault: &TripVault, vault_ata_amount: u64) -> Result<()> {
    let expected = vault
        .total_deposited
        .checked_sub(vault.total_spent)
        .ok_or(VaultError::Overflow)?;
    require!(expected == vault_ata_amount, VaultError::InvariantViolated);
    Ok(())
}
