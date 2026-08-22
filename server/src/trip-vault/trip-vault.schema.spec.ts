import {
  PrismaClient,
  VaultStatus,
  VaultTxKind,
  VaultTxStatus,
  WalletProvider,
} from '@prisma/client';

/**
 * Guards the shape the rest of the module depends on. It runs against the
 * generated client rather than a live database, so it stays fast.
 */
describe('trip vault schema', () => {
  const prisma = new PrismaClient();

  it('exposes the three vault models', () => {
    expect(prisma.tripVault).toBeDefined();
    expect(prisma.walletAccount).toBeDefined();
    expect(prisma.vaultTransaction).toBeDefined();
  });

  it('exposes the vault enums', () => {
    expect(VaultStatus.ACTIVE).toBe('ACTIVE');
    expect(VaultStatus.SETTLING).toBe('SETTLING');
    expect(VaultStatus.CLOSED).toBe('CLOSED');
    expect(WalletProvider.PRIVY).toBe('PRIVY');
    expect(VaultTxKind.DEPOSIT).toBe('DEPOSIT');
    expect(VaultTxKind.SPEND).toBe('SPEND');
    expect(VaultTxKind.REVERT).toBe('REVERT');
    expect(VaultTxKind.SETTLEMENT).toBe('SETTLEMENT');
    expect(VaultTxStatus.PENDING).toBe('PENDING');
    expect(VaultTxStatus.CONFIRMED).toBe('CONFIRMED');
    expect(VaultTxStatus.FAILED).toBe('FAILED');
  });
});
