/** Below $0.01 USDC — treat as settled (matches iOS leave sheet). */
export const VAULT_LEAVE_DUST_MICRO = 10_000n;

export function isMeaningfulVaultCredit(netMicro: bigint): boolean {
  return netMicro >= VAULT_LEAVE_DUST_MICRO;
}

export function isMeaningfulVaultDebt(netMicro: bigint): boolean {
  return netMicro <= -VAULT_LEAVE_DUST_MICRO;
}

/** Floor sub-cent balances to 0 for leave announce / host display. */
export function floorVaultLeaveNet(netMicro: bigint): bigint {
  if (!isMeaningfulVaultCredit(netMicro) && !isMeaningfulVaultDebt(netMicro)) {
    return 0n;
  }
  return netMicro;
}
