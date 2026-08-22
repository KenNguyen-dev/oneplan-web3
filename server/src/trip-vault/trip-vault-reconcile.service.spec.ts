import { ExpenseCategory, VaultTxKind, VaultTxStatus } from '@prisma/client';
import { Keypair } from '@solana/web3.js';

import { TripVaultReconcileService } from './trip-vault-reconcile.service';

function row(overrides: Record<string, unknown> = {}) {
  return {
    id: 1,
    tripVaultId: 1,
    userId: 7,
    kind: VaultTxKind.SPEND,
    status: VaultTxStatus.PENDING,
    amountMicro: 7_660_000n,
    amountVnd: 200_000n,
    bankBin: '970412',
    bankAccount: '109000636588',
    payoutRef: 'vault-tx-1',
    payoutStatus: null,
    signature: 'sig',
    failureCode: null,
    expenseName: 'Coffee',
    expenseCategory: ExpenseCategory.COFFEE,
    shareWithUserIds: [7, 8],
    createdAt: new Date(Date.now() - 10 * 60_000),
    ...overrides,
  };
}

/**
 * The service runs five independent queries in order. Each test supplies the
 * rows for the branch it exercises and empty arrays for the rest.
 */
function deps(
  branches: {
    broadcastDeposits?: unknown[];
    missingPayout?: unknown[];
    pending?: unknown[];
    toRevert?: unknown[];
  } = {},
) {
  const findMany = jest
    .fn()
    .mockResolvedValueOnce(branches.broadcastDeposits ?? [])
    .mockResolvedValueOnce(branches.missingPayout ?? [])
    .mockResolvedValueOnce(branches.pending ?? [])
    .mockResolvedValueOnce(branches.toRevert ?? [])
    .mockResolvedValue([]);

  const prisma = {
    vaultTransaction: { findMany, update: jest.fn() },
    tripVault: {
      findMany: jest.fn().mockResolvedValue([]),
      findUniqueOrThrow: jest.fn().mockResolvedValue({
        tripId: 42,
        vaultPda: Keypair.generate().publicKey.toBase58(),
        usdcAta: Keypair.generate().publicKey.toBase58(),
      }),
    },
  };
  const payout = { payout: jest.fn(), getStatus: jest.fn() };
  const solana = {
    isConfigured: true,
    getTokenBalance: jest.fn().mockResolvedValue(0n),
    revertSpend: jest.fn().mockResolvedValue('revert-sig'),
    signatureLanded: jest.fn().mockResolvedValue(true),
  };
  const expenses = { createFromVault: jest.fn().mockResolvedValue({ id: 55 }) };
  return { prisma, payout, solana, expenses };
}

function build(d: ReturnType<typeof deps>) {
  return new TripVaultReconcileService(
    d.prisma as never,
    d.payout as never,
    d.solana as never,
    d.expenses as never,
  );
}

describe('TripVaultReconcileService', () => {
  it('sends the payout when the chain leg landed but the fiat leg never started', async () => {
    const d = deps({ missingPayout: [row({ payoutStatus: null })] });
    d.payout.payout.mockResolvedValue({ outcome: 'SUCCESS' });

    const report = await build(d).reconcile();

    expect(d.payout.payout).toHaveBeenCalledWith(
      expect.objectContaining({ reference: 'vault-tx-1' }),
    );
    expect(report.payoutsSent).toBe(1);
  });

  it('confirms a pending row once the provider reports SUCCESS', async () => {
    const d = deps({ pending: [row({ payoutStatus: 'UNKNOWN' })] });
    d.payout.getStatus.mockResolvedValue('SUCCESS');

    const report = await build(d).reconcile();

    expect(report.confirmed).toBe(1);
    expect(d.expenses.createFromVault).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'Coffee',
        category: ExpenseCategory.COFFEE,
        shareWithUserIds: [7, 8],
      }),
    );
    expect(d.solana.revertSpend).not.toHaveBeenCalled();
  });

  it('never reverts while the provider still reports UNKNOWN', async () => {
    const d = deps({ pending: [row({ payoutStatus: 'UNKNOWN' })] });
    d.payout.getStatus.mockResolvedValue('UNKNOWN');

    const report = await build(d).reconcile();

    expect(d.solana.revertSpend).not.toHaveBeenCalled();
    expect(d.expenses.createFromVault).not.toHaveBeenCalled();
    expect(report.reverted).toBe(0);
  });

  it('marks a pending row failed once the provider confirms FAILED', async () => {
    const d = deps({ pending: [row({ payoutStatus: 'UNKNOWN' })] });
    d.payout.getStatus.mockResolvedValue('FAILED');

    await build(d).reconcile();

    const updates = d.prisma.vaultTransaction.update.mock.calls as Array<
      [{ data: { status?: VaultTxStatus } }]
    >;
    expect(
      updates.some(([arg]) => arg.data.status === VaultTxStatus.FAILED),
    ).toBe(true);
    expect(d.expenses.createFromVault).not.toHaveBeenCalled();
  });

  it('reverts only rows already confirmed FAILED', async () => {
    const d = deps({ toRevert: [row({ status: VaultTxStatus.FAILED })] });

    const report = await build(d).reconcile();

    expect(d.solana.revertSpend).toHaveBeenCalled();
    expect(report.reverted).toBe(1);
  });

  it('flags a row stuck PENDING for over thirty minutes', async () => {
    const d = deps({
      pending: [
        row({
          payoutStatus: 'UNKNOWN',
          createdAt: new Date(Date.now() - 45 * 60_000),
        }),
      ],
    });
    d.payout.getStatus.mockResolvedValue('UNKNOWN');

    const report = await build(d).reconcile();

    expect(report.stale).toBe(1);
  });

  it('does nothing at all when Solana is not configured', async () => {
    const d = deps({ missingPayout: [row()] });
    d.solana.isConfigured = false;

    await build(d).handleCron();

    expect(d.payout.payout).not.toHaveBeenCalled();
  });

  it('confirms a deposit whose broadcast answer never came back', async () => {
    const d = deps({
      broadcastDeposits: [
        row({ id: 9, kind: VaultTxKind.DEPOSIT, signature: 'dep-sig' }),
      ],
    });
    d.solana.signatureLanded.mockResolvedValue(true);

    await build(d).reconcile();

    expect(d.solana.signatureLanded).toHaveBeenCalledWith('dep-sig');
    expect(d.prisma.vaultTransaction.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { status: VaultTxStatus.CONFIRMED },
      }),
    );
  });

  // A deposit whose transaction never landed is money the vault does not have.
  // Left PENDING it reads as a contribution nobody can spend.
  it('fails a deposit whose transaction never reached the chain', async () => {
    const d = deps({
      broadcastDeposits: [
        row({ id: 9, kind: VaultTxKind.DEPOSIT, signature: 'dep-sig' }),
      ],
    });
    d.solana.signatureLanded.mockResolvedValue(false);

    await build(d).reconcile();

    expect(d.prisma.vaultTransaction.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { status: VaultTxStatus.FAILED } }),
    );
  });

  // The payout provider takes bank details a deposit does not have, so a
  // deposit reaching that branch would call it with nulls.
  it('never sends a payout for a deposit', async () => {
    const d = deps({
      broadcastDeposits: [
        row({ id: 9, kind: VaultTxKind.DEPOSIT, signature: 'dep-sig' }),
      ],
    });

    await build(d).reconcile();

    expect(d.payout.payout).not.toHaveBeenCalled();
  });
});
