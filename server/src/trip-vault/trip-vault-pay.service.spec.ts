import { BadRequestException, NotFoundException } from '@nestjs/common';
import { ExpenseCategory, VaultTxStatus } from '@prisma/client';
import { Keypair } from '@solana/web3.js';

import { TripVaultPayService } from './trip-vault-pay.service';

/** Static VietQR: PVcomBank 970412, account 109000636588, no amount. */
function tlv(tag: string, value: string): string {
  return tag + String(value.length).padStart(2, '0') + value;
}
const STATIC_QR = (() => {
  const merchant =
    tlv('00', 'A000000727') +
    tlv('01', tlv('00', '970412') + tlv('01', '109000636588')) +
    tlv('02', 'QRIBFTTA');
  return (
    tlv('00', '01') +
    tlv('01', '11') +
    tlv('38', merchant) +
    tlv('53', '704') +
    tlv('58', 'VN') +
    tlv('63', 'ABCD')
  );
})();

function deps() {
  // Prisma's update returns the whole row, not just the changed columns, and the
  // service reads status off the result. A mock that returns only `data` would
  // make the UNKNOWN branch look like it cleared the status.
  let current: Record<string, unknown> = {};
  const prisma = {
    vaultTransaction: {
      create: jest.fn().mockResolvedValue({ id: 9 }),
      update: jest
        .fn()
        .mockImplementation((args: { data: Record<string, unknown> }) => {
          current = { ...current, ...args.data };
          return Promise.resolve(current);
        }),
      findUnique: jest.fn().mockImplementation(() => Promise.resolve(current)),
      findUniqueOrThrow: jest
        .fn()
        .mockImplementation(() => Promise.resolve(current)),
    },
    tripVault: {
      findUniqueOrThrow: jest.fn().mockResolvedValue({ tripId: 42 }),
    },
    walletAccount: { findUnique: jest.fn() },
    user: { findUnique: jest.fn().mockResolvedValue({ displayName: 'Ana' }) },
  };
  const vaultService = {
    requireVault: jest.fn().mockResolvedValue({
      id: 1,
      tripId: 42,
      vaultPda: Keypair.generate().publicKey.toBase58(),
      usdcAta: Keypair.generate().publicKey.toBase58(),
      thresholdMicro: 10_000_000n,
    }),
    getBalance: jest.fn().mockResolvedValue({ balanceMicro: 100_000_000n }),
    invalidateBalance: jest.fn(),
    approverUserIds: jest.fn().mockResolvedValue(null),
  };
  const solana = {
    broadcastSigned: jest.fn().mockResolvedValue('sig-123'),
    confirmSigned: jest.fn().mockResolvedValue(undefined),
    signatureLanded: jest.fn().mockResolvedValue(true),
    usdcMint: Keypair.generate().publicKey,
    feePayer: Keypair.generate(),
    receiverPublicKey: Keypair.generate().publicKey,
    buildUnsignedTx: jest.fn().mockResolvedValue('base64tx'),
    program: {
      methods: {
        spend: () => ({ accountsPartial: () => ({ instruction: jest.fn() }) }),
        proposeSpend: () => ({
          accountsPartial: () => ({ instruction: jest.fn() }),
        }),
        approveSpend: () => ({
          accountsPartial: () => ({ instruction: jest.fn() }),
        }),
        cancelSpend: () => ({
          accountsPartial: () => ({ instruction: jest.fn() }),
        }),
      },
      account: {
        tripVault: {
          fetch: jest.fn().mockResolvedValue({
            hasActiveSpend: true,
            totalSpent: { toString: () => '0' },
          }),
        },
      },
    },
  };
  const payout = {
    validateRecipient: jest
      .fn()
      .mockResolvedValue({ accountName: 'NGUYEN VAN A' }),
    quote: jest.fn().mockResolvedValue({
      amountUsdcMicro: 7_660_000n,
      feeMicro: 57_450n,
      rate: '26500',
    }),
    payout: jest.fn().mockResolvedValue({ outcome: 'SUCCESS' }),
    getStatus: jest.fn(),
  };
  const expenses = { createFromVault: jest.fn().mockResolvedValue({ id: 55 }) };
  const trips = {
    sendVaultApprovalRequested: jest.fn(),
    sendVaultBalanceChanged: jest.fn(),
  };
  const seed = (row: Record<string, unknown>) => {
    current = { ...row };
    prisma.vaultTransaction.findUnique.mockResolvedValue(current);
  };
  return { prisma, vaultService, solana, payout, expenses, trips, seed };
}

function build(d: ReturnType<typeof deps>): TripVaultPayService {
  return new TripVaultPayService(
    d.prisma as never,
    d.vaultService as never,
    d.solana as never,
    d.payout as never,
    d.expenses as never,
    d.trips as never,
  );
}

const TRIP_ID = 42;

function pendingRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 9,
    tripVaultId: 1,
    // Present because submitPayment/buildApprovalTx load the row with the vault
    // joined in, to prove the transaction belongs to the trip in the URL.
    tripVault: { tripId: TRIP_ID },
    userId: 7,
    amountMicro: 7_660_000n,
    amountVnd: 200_000n,
    bankBin: '970412',
    bankAccount: '109000636588',
    status: VaultTxStatus.PENDING,
    payoutRef: 'vault-tx-9',
    expenseName: 'Coffee',
    expenseCategory: ExpenseCategory.COFFEE,
    shareWithUserIds: [7, 8],
    ...overrides,
  };
}

describe('TripVaultPayService', () => {
  it('derives a deterministic payout reference', () => {
    expect(build(deps()).payoutRefFor(7)).toBe('vault-tx-7');
  });

  it('rejects a payment above the vault balance', async () => {
    const d = deps();
    d.vaultService.getBalance.mockResolvedValue({ balanceMicro: 1_000n });

    await expect(build(d).quote(42, 7, STATIC_QR, 200_000n)).rejects.toThrow(
      BadRequestException,
    );
  });

  it('rejects a static QR with no amount supplied', async () => {
    await expect(build(deps()).quote(42, 7, STATIC_QR)).rejects.toThrow(
      /amount/i,
    );
  });

  it('rejects a recipient the provider cannot validate', async () => {
    const d = deps();
    d.payout.validateRecipient.mockResolvedValue(null);

    await expect(build(d).quote(42, 7, STATIC_QR, 200_000n)).rejects.toThrow(
      /recipient/i,
    );
  });

  it('flags amounts above the threshold as needing approval', async () => {
    const d = deps();
    d.payout.quote.mockResolvedValue({
      amountUsdcMicro: 50_000_000n,
      feeMicro: 0n,
      rate: '26500',
    });

    const quote = await build(d).quote(42, 7, STATIC_QR, 1_325_000_000n);
    expect(quote.needsApproval).toBe(true);
  });

  it('does not flag amounts at the threshold', async () => {
    const d = deps();
    d.payout.quote.mockResolvedValue({
      amountUsdcMicro: 10_000_000n,
      feeMicro: 0n,
      rate: '26500',
    });

    const quote = await build(d).quote(42, 7, STATIC_QR, 265_000_000n);
    expect(quote.needsApproval).toBe(false);
  });

  it('creates the expense with its split when the payout succeeds', async () => {
    const d = deps();
    d.seed(pendingRow());
    d.vaultService.requireVault.mockResolvedValue({ id: 1, tripId: 42 });

    const result = await build(d).submitPayment(9, 'base64signed', TRIP_ID);

    expect(result.status).toBe(VaultTxStatus.CONFIRMED);
    expect(d.expenses.createFromVault).toHaveBeenCalledWith(
      expect.objectContaining({
        tripId: 42,
        name: 'Coffee',
        category: ExpenseCategory.COFFEE,
        shareWithUserIds: [7, 8],
      }),
    );
  });

  // The proposal's address is not knowable before the transaction that creates
  // it runs. Deriving it beforehand left rows pointing at accounts that never
  // existed, and gave two members preparing at once the same address.
  it('records the proposal address the chain actually used', async () => {
    const d = deps();
    d.seed(pendingRow({ amountMicro: 20_000_000n, proposalPda: null }));
    d.vaultService.requireVault.mockResolvedValue({
      id: 1,
      tripId: TRIP_ID,
      vaultPda: Keypair.generate().publicKey.toBase58(),
      thresholdMicro: 10_000_000n,
    });

    await build(d).submitPayment(9, 'base64signed', TRIP_ID);

    expect(d.prisma.vaultTransaction.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ proposalPda: expect.any(String) }),
      }),
    );
  });

  // Asking for an approval before the proposal exists invites the other member
  // to sign something that can only fail.
  it('asks for approval only once the proposal is on chain', async () => {
    const d = deps();
    d.seed(pendingRow({ amountMicro: 20_000_000n, proposalPda: null }));
    d.vaultService.requireVault.mockResolvedValue({
      id: 1,
      tripId: TRIP_ID,
      vaultPda: Keypair.generate().publicKey.toBase58(),
      thresholdMicro: 10_000_000n,
    });

    d.prisma.walletAccount.findUnique.mockResolvedValue({
      publicKey: Keypair.generate().publicKey.toBase58(),
    });
    d.payout.quote.mockResolvedValue({
      amountUsdcMicro: 20_000_000n,
      feeMicro: 0n,
      rate: '26500',
    });

    await build(d).preparePayment(TRIP_ID, 7, {
      qrPayload: STATIC_QR,
      amountVnd: 530_000_000n,
      name: 'Dinner',
      category: ExpenseCategory.FOOD,
      shareWithUserIds: [7],
    });
    expect(d.trips.sendVaultApprovalRequested).not.toHaveBeenCalled();

    await build(d).submitPayment(9, 'base64signed', TRIP_ID);
    expect(d.trips.sendVaultApprovalRequested).toHaveBeenCalled();
  });

  // The vault must not pay a merchant for money still sitting in it.
  it('does not pay the merchant on the proposal leg', async () => {
    const d = deps();
    d.seed(pendingRow({ amountMicro: 20_000_000n, proposalPda: null }));
    d.vaultService.requireVault.mockResolvedValue({
      id: 1,
      tripId: TRIP_ID,
      vaultPda: Keypair.generate().publicKey.toBase58(),
      thresholdMicro: 10_000_000n,
    });

    await build(d).submitPayment(9, 'base64signed', TRIP_ID);

    expect(d.payout.payout).not.toHaveBeenCalled();
  });

  it('marks the row failed when the payout is confirmed FAILED', async () => {
    const d = deps();
    d.seed(pendingRow());
    d.payout.payout.mockResolvedValue({
      outcome: 'FAILED',
      failureCode: 'MOCK_DECLINED',
    });

    const result = await build(d).submitPayment(9, 'base64signed', TRIP_ID);

    expect(result.status).toBe(VaultTxStatus.FAILED);
    expect(d.expenses.createFromVault).not.toHaveBeenCalled();
  });

  it('leaves the transaction PENDING when the payout is UNKNOWN', async () => {
    const d = deps();
    d.seed(pendingRow());
    d.payout.payout.mockResolvedValue({ outcome: 'UNKNOWN' });

    const result = await build(d).submitPayment(9, 'base64signed', TRIP_ID);

    // The critical assertion: an ambiguous payout must not create an expense and
    // must not mark the row failed, because a revert would then pay twice.
    expect(result.status).toBe(VaultTxStatus.PENDING);
    expect(d.expenses.createFromVault).not.toHaveBeenCalled();
  });

  it('is idempotent: a row that is no longer PENDING is returned untouched', async () => {
    const d = deps();
    d.seed(pendingRow({ status: VaultTxStatus.CONFIRMED }));

    const result = await build(d).submitPayment(9, 'base64signed', TRIP_ID);

    expect(result.status).toBe(VaultTxStatus.CONFIRMED);
    expect(d.solana.broadcastSigned).not.toHaveBeenCalled();
    expect(d.payout.payout).not.toHaveBeenCalled();
  });

  it('refuses a transaction that belongs to a different trip', async () => {
    const d = deps();
    d.seed(pendingRow());

    // The route nests the transaction under a trip. Without this check the trip
    // segment is decorative and any member of any trip could spend another
    // trip's vault just by guessing a transaction id.
    await expect(
      build(d).submitPayment(9, 'base64signed', TRIP_ID + 1),
    ).rejects.toThrow(NotFoundException);

    expect(d.solana.broadcastSigned).not.toHaveBeenCalled();
    expect(d.payout.payout).not.toHaveBeenCalled();
  });
});
