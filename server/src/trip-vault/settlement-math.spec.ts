import {
  cashDebtLines,
  cashDebts,
  computeSettlement,
  splitEvenly,
} from './settlement-math';

describe('splitEvenly', () => {
  it('splits exactly when the amount divides', () => {
    const split = splitEvenly(300n, [1, 2, 3]);
    expect([...split.values()]).toEqual([100n, 100n, 100n]);
  });

  it('gives the remainder to the earliest ids so nothing is lost', () => {
    const split = splitEvenly(100n, [1, 2, 3]);
    expect(split.get(1)).toBe(34n);
    expect(split.get(2)).toBe(33n);
    expect(split.get(3)).toBe(33n);
    expect([...split.values()].reduce((a, b) => a + b, 0n)).toBe(100n);
  });

  it('is order independent', () => {
    expect([...splitEvenly(100n, [3, 1, 2])]).toEqual([
      ...splitEvenly(100n, [1, 2, 3]),
    ]);
  });

  it('returns nothing for an empty member list', () => {
    expect(splitEvenly(100n, []).size).toBe(0);
  });
});

describe('computeSettlement', () => {
  it('returns each depositor their surplus when everyone paid in', () => {
    const result = computeSettlement({
      memberIds: [1, 2],
      depositsByUser: new Map([
        [1, 100_000_000n],
        [2, 100_000_000n],
      ]),
      spends: [{ amountMicro: 100_000_000n, shareWithUserIds: [1, 2] }],
      balanceMicro: 100_000_000n,
    });

    expect(result.map((r) => r.onChainMicro)).toEqual([50_000_000n, 50_000_000n]);
    expect(result.every((r) => r.offChainMicro === 0n)).toBe(true);
  });

  it('leaves the shortfall off chain when a member never deposited', () => {
    // The case the product exists for: two travellers hold crypto, the third
    // does not and settles in cash afterwards.
    const result = computeSettlement({
      memberIds: [1, 2, 3],
      depositsByUser: new Map([
        [1, 100_000_000n],
        [2, 100_000_000n],
      ]),
      spends: [{ amountMicro: 150_000_000n, shareWithUserIds: [1, 2, 3] }],
      balanceMicro: 50_000_000n,
    });

    const [alice, bob, carol] = result;

    expect(alice.netMicro).toBe(50_000_000n);
    expect(bob.netMicro).toBe(50_000_000n);
    expect(carol.netMicro).toBe(-50_000_000n);

    // Half of what each is owed arrives on chain...
    expect(alice.onChainMicro).toBe(25_000_000n);
    expect(bob.onChainMicro).toBe(25_000_000n);
    // ...and the rest is exactly what Carol owes them.
    expect(alice.offChainMicro + bob.offChainMicro).toBe(50_000_000n);
    expect(carol.onChainMicro).toBe(0n);
  });

  it('never pays out more than the vault holds', () => {
    const result = computeSettlement({
      memberIds: [1, 2],
      depositsByUser: new Map([[1, 100_000_000n]]),
      spends: [],
      balanceMicro: 10_000_000n,
    });

    const total = result.reduce((sum, r) => sum + r.onChainMicro, 0n);
    expect(total).toBe(10_000_000n);
  });

  it('pays out the balance exactly, with no rounding dust left behind', () => {
    const result = computeSettlement({
      memberIds: [1, 2, 3],
      depositsByUser: new Map([
        [1, 1n],
        [2, 1n],
        [3, 1n],
      ]),
      spends: [{ amountMicro: 2n, shareWithUserIds: [1, 2, 3] }],
      balanceMicro: 1n,
    });

    const total = result.reduce((sum, r) => sum + r.onChainMicro, 0n);
    expect(total).toBe(1n);
  });

  it('treats an empty share list as everyone', () => {
    const result = computeSettlement({
      memberIds: [1, 2],
      depositsByUser: new Map([[1, 100n]]),
      spends: [{ amountMicro: 100n, shareWithUserIds: [] }],
      balanceMicro: 0n,
    });

    expect(result.find((r) => r.userId === 1)?.netMicro).toBe(50n);
    expect(result.find((r) => r.userId === 2)?.netMicro).toBe(-50n);
  });

  it('holds the invariant that net positions sum to the balance', () => {
    const input = {
      memberIds: [1, 2, 3, 4],
      depositsByUser: new Map([
        [1, 70_000_000n],
        [2, 30_000_000n],
        [4, 11_111_111n],
      ]),
      spends: [
        { amountMicro: 33_333_333n, shareWithUserIds: [1, 2, 3] },
        { amountMicro: 7_777_777n, shareWithUserIds: [] },
      ],
      balanceMicro: 70_000_000n + 30_000_000n + 11_111_111n - 33_333_333n - 7_777_777n,
    };

    const result = computeSettlement(input);
    const netTotal = result.reduce((sum, r) => sum + r.netMicro, 0n);

    expect(netTotal).toBe(input.balanceMicro);
    expect(result.reduce((sum, r) => sum + r.onChainMicro, 0n)).toBe(
      input.balanceMicro,
    );
  });

  it('pays nobody when the vault is empty', () => {
    const result = computeSettlement({
      memberIds: [1, 2],
      depositsByUser: new Map([[1, 100n]]),
      spends: [{ amountMicro: 100n, shareWithUserIds: [1, 2] }],
      balanceMicro: 0n,
    });

    expect(result.every((r) => r.onChainMicro === 0n)).toBe(true);
    expect(result.find((r) => r.userId === 1)?.offChainMicro).toBe(50n);
  });
});

describe('cashDebts', () => {
  const shares = (
    entries: [number, bigint, bigint][],
  ) =>
    entries.map(([userId, netMicro, offChainMicro]) => ({
      userId,
      netMicro,
      onChainMicro: 0n,
      offChainMicro,
    }));

  it('names both sides of every debt', () => {
    // Alice and Bob are each short 25 after the vault pays out; Carol owes 50.
    const debts = cashDebts(
      shares([
        [1, 50_000_000n, 25_000_000n],
        [2, 50_000_000n, 25_000_000n],
        [3, -50_000_000n, 0n],
      ]),
    );

    expect(debts).toHaveLength(2);
    expect(debts.every((d) => d.fromUserId === 3)).toBe(true);
    expect(debts.map((d) => d.toUserId).sort()).toEqual([1, 2]);
    expect(debts.reduce((sum, d) => sum + d.amountMicro, 0n)).toBe(50_000_000n);
  });

  it('splits one debtor across several creditors', () => {
    const debts = cashDebts(
      shares([
        [1, 60n, 60n],
        [2, 40n, 40n],
        [3, -100n, 0n],
      ]),
    );

    expect(debts).toEqual([
      { fromUserId: 3, toUserId: 1, amountMicro: 60n },
      { fromUserId: 3, toUserId: 2, amountMicro: 40n },
    ]);
  });

  it('splits one creditor across several debtors', () => {
    const debts = cashDebts(
      shares([
        [1, 100n, 100n],
        [2, -60n, 0n],
        [3, -40n, 0n],
      ]),
    );

    expect(debts.reduce((sum, d) => sum + d.amountMicro, 0n)).toBe(100n);
    expect(debts.every((d) => d.toUserId === 1)).toBe(true);
  });

  it('is stable, so a debt keeps its identity between requests', () => {
    const input = shares([
      [7, 50n, 50n],
      [3, 50n, 50n],
      [9, -100n, 0n],
    ]);
    expect(cashDebts(input)).toEqual(cashDebts([...input].reverse()));
  });

  it('produces nothing when the vault covered everyone', () => {
    expect(cashDebts(shares([[1, 50n, 0n], [2, -50n, 0n]]))).toEqual([]);
  });
});

describe('cashDebtLines', () => {
  it('scales debtor spend shares so lines sum to the cash debt', () => {
    const lines = cashDebtLines(
      { fromUserId: 1, toUserId: 2, amountMicro: 1_000_000n },
      [
        {
          amountMicro: 2_000_000n,
          shareWithUserIds: [1],
          title: 'Breakfast',
        },
        {
          amountMicro: 8_000_000n,
          shareWithUserIds: [],
          title: 'Coffee',
        },
      ],
      [1, 2],
    );

    // Huy-only breakfast weight 2M; coffee All → Huy share 4M; ratio 1:2 → 333333 + 666667
    expect(lines.reduce((sum, line) => sum + line.amountMicro, 0n)).toBe(
      1_000_000n,
    );
    expect(lines.map((line) => line.title)).toEqual(['Breakfast', 'Coffee']);
  });

  it('falls back to a single Settlement line when the debtor has no spends', () => {
    expect(
      cashDebtLines(
        { fromUserId: 1, toUserId: 2, amountMicro: 500n },
        [{ amountMicro: 100n, shareWithUserIds: [2], title: 'Only Bob' }],
        [1, 2],
      ),
    ).toEqual([{ title: 'Settlement', amountMicro: 500n }]);
  });
});
