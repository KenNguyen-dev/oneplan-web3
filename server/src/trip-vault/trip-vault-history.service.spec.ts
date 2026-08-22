import { VaultTxKind } from '@prisma/client';

import { TripVaultHistoryService } from './trip-vault-history.service';

describe('TripVaultHistoryService.getHistory forUserId', () => {
  const HUY = 1;
  const BORON = 2;
  const TRIP_ID = 10;

  function build(rows: Array<Record<string, unknown>>) {
    const prisma = {
      vaultTransaction: {
        findMany: jest.fn().mockResolvedValue(rows),
      },
      tripMember: {
        count: jest.fn().mockResolvedValue(2),
      },
      user: {
        findMany: jest.fn().mockResolvedValue([
          { id: HUY, displayName: 'Huy', avatarUrl: null },
          { id: BORON, displayName: 'Boron', avatarUrl: null },
        ]),
      },
      walletAccount: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const vaultService = {
      requireVault: jest.fn().mockResolvedValue({ id: 99 }),
    };
    const service = new TripVaultHistoryService(
      prisma as any,
      vaultService as any,
    );
    return { service, prisma };
  }

  function row(
    overrides: Partial<{
      id: number;
      kind: VaultTxKind;
      userId: number | null;
      shareWithUserIds: number[];
      expenseName: string;
    }>,
  ) {
    return {
      id: overrides.id ?? 1,
      kind: overrides.kind ?? VaultTxKind.SPEND,
      status: 'CONFIRMED',
      proposalPda: null,
      approvedAt: null,
      userId: overrides.userId ?? null,
      user: overrides.userId
        ? { id: overrides.userId, displayName: 'X', avatarUrl: null }
        : null,
      shareWithUserIds: overrides.shareWithUserIds ?? [],
      amountMicro: 1_000_000n,
      amountVnd: 20_000n,
      expenseName: overrides.expenseName ?? 'Item',
      expenseCategory: 'FOOD',
      signature: null,
      createdAt: new Date('2026-08-19T00:00:00.000Z'),
      expense: null,
    };
  }

  it('hides another member deposit and Huy-only spend from Boron', async () => {
    const { service } = build([
      row({
        id: 1,
        kind: VaultTxKind.SPEND,
        userId: HUY,
        shareWithUserIds: [HUY],
        expenseName: 'Breakfast',
      }),
      row({
        id: 2,
        kind: VaultTxKind.SPEND,
        userId: HUY,
        shareWithUserIds: [],
        expenseName: 'Coffee',
      }),
      row({
        id: 3,
        kind: VaultTxKind.DEPOSIT,
        userId: HUY,
        expenseName: 'Deposit',
      }),
      row({
        id: 4,
        kind: VaultTxKind.DEPOSIT,
        userId: BORON,
        expenseName: 'Deposit',
      }),
    ]);

    const history = await service.getHistory(TRIP_ID, BORON);
    expect(history.map((e) => e.id)).toEqual([2, 4]);
  });

  it('keeps Huy-only breakfast on Huy review', async () => {
    const { service } = build([
      row({
        id: 1,
        kind: VaultTxKind.SPEND,
        userId: HUY,
        shareWithUserIds: [HUY],
        expenseName: 'Breakfast',
      }),
    ]);

    const history = await service.getHistory(TRIP_ID, HUY);
    expect(history.map((e) => e.id)).toEqual([1]);
  });

  it('hides Huy-only spend from Boron even when Boron submitted the pay', async () => {
    const { service } = build([
      row({
        id: 1,
        kind: VaultTxKind.SPEND,
        userId: BORON,
        shareWithUserIds: [HUY],
        expenseName: 'Coffee',
      }),
    ]);

    const history = await service.getHistory(TRIP_ID, BORON);
    expect(history.map((e) => e.id)).toEqual([]);
  });

  it('without forUserId returns the full ledger', async () => {
    const { service } = build([
      row({ id: 1, kind: VaultTxKind.DEPOSIT, userId: HUY }),
      row({ id: 2, kind: VaultTxKind.DEPOSIT, userId: BORON }),
    ]);

    const history = await service.getHistory(TRIP_ID);
    expect(history.map((e) => e.id)).toEqual([1, 2]);
  });
});
