import {
  floorVaultLeaveNet,
  isMeaningfulVaultCredit,
  isMeaningfulVaultDebt,
  VAULT_LEAVE_DUST_MICRO,
} from './vault-leave-dust';

describe('vault-leave-dust', () => {
  it('treats sub-cent as not meaningful credit or debt', () => {
    expect(isMeaningfulVaultCredit(9_999n)).toBe(false);
    expect(isMeaningfulVaultDebt(-9_999n)).toBe(false);
    expect(floorVaultLeaveNet(1_200n)).toBe(0n);
    expect(floorVaultLeaveNet(-500n)).toBe(0n);
  });

  it('keeps ≥ $0.01 credits and debts', () => {
    expect(isMeaningfulVaultCredit(VAULT_LEAVE_DUST_MICRO)).toBe(true);
    expect(isMeaningfulVaultDebt(-VAULT_LEAVE_DUST_MICRO)).toBe(true);
    expect(floorVaultLeaveNet(1_890_000n)).toBe(1_890_000n);
    expect(floorVaultLeaveNet(-1_890_000n)).toBe(-1_890_000n);
  });
});

describe('leave settlement deposit receipt', () => {
  it('keeps meaningful credit/debt floors', () => {
    expect(isMeaningfulVaultCredit(1_890_000n)).toBe(true);
    expect(isMeaningfulVaultDebt(-1_890_000n)).toBe(true);
  });
});
