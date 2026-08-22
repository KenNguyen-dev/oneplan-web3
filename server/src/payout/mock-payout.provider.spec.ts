import { ConfigService } from '@nestjs/config';
import { MockPayoutProvider } from './mock-payout.provider';

function provider(outcome = 'success'): MockPayoutProvider {
  const config = {
    get: (k: string, d?: string) => (k === 'MOCK_PAYOUT_OUTCOME' ? outcome : d),
  } as ConfigService;
  return new MockPayoutProvider(config);
}

describe('MockPayoutProvider', () => {
  it('returns a deterministic account name for a valid recipient', async () => {
    const result = await provider().validateRecipient({
      bankBin: '970412',
      accountNumber: '109000636588',
    });
    expect(result).not.toBeNull();
    expect(result!.accountName.length).toBeGreaterThan(0);
  });

  it('accepts any NAPAS BIN from the bank name map', async () => {
    const result = await provider().validateRecipient({
      bankBin: '970437', // HDBank — was missing from the old shortlist
      accountNumber: '109000636588',
    });
    expect(result).not.toBeNull();
  });

  it('accepts MoMo wallet VietQR via BVBank virtual accounts', async () => {
    const result = await provider().validateRecipient({
      bankBin: '970454',
      accountNumber: '99MM24011M34875080',
    });
    expect(result).toEqual({ accountName: 'MOMO WALLET' });
  });

  it('rejects an unknown bank bin', async () => {
    const result = await provider().validateRecipient({
      bankBin: '000000',
      accountNumber: '109000636588',
    });
    expect(result).toBeNull();
  });

  it('rejects a malformed account number', async () => {
    const result = await provider().validateRecipient({
      bankBin: '970412',
      accountNumber: 'abc',
    });
    expect(result).toBeNull();
  });

  it('quotes VND to micro-USDC at the configured rate', async () => {
    const quote = await provider().quote({ amountVnd: 265_000n });
    // 265,000 VND at 26,500 VND per USDC is 10 USDC, and the fee is 0.75%.
    expect(quote.amountUsdcMicro).toBe(10_000_000n);
    expect(quote.feeMicro).toBe(75_000n);
    expect(quote.rate).toBe('26500');
  });

  it('reports SUCCESS and remembers the reference', async () => {
    const p = provider('success');
    const result = await p.payout({
      bankBin: '970412',
      accountNumber: '109000636588',
      amountVnd: 200_000n,
      reference: 'vault-tx-1',
    });
    expect(result.outcome).toBe('SUCCESS');
    expect(await p.getStatus('vault-tx-1')).toBe('SUCCESS');
  });

  it('reports FAILED when configured to fail', async () => {
    const p = provider('failed');
    const result = await p.payout({
      bankBin: '970412',
      accountNumber: '1',
      amountVnd: 1n,
      reference: 'vault-tx-2',
    });
    expect(result.outcome).toBe('FAILED');
    expect(result.failureCode).toBeDefined();
    expect(await p.getStatus('vault-tx-2')).toBe('FAILED');
  });

  it('reports UNKNOWN on a timeout and resolves to SUCCESS afterwards', async () => {
    const p = provider('timeout');
    const result = await p.payout({
      bankBin: '970412',
      accountNumber: '1',
      amountVnd: 1n,
      reference: 'vault-tx-3',
    });
    // The dangerous case: the caller must not treat this as a failure, because
    // the money did in fact move.
    expect(result.outcome).toBe('UNKNOWN');
    expect(await p.getStatus('vault-tx-3')).toBe('SUCCESS');
  });

  it('stays UNKNOWN when configured to never resolve', async () => {
    const p = provider('unknown');
    await p.payout({
      bankBin: '970412',
      accountNumber: '1',
      amountVnd: 1n,
      reference: 'vault-tx-4',
    });
    expect(await p.getStatus('vault-tx-4')).toBe('UNKNOWN');
  });

  it('is idempotent on the reference', async () => {
    const p = provider('success');
    const input = {
      bankBin: '970412',
      accountNumber: '1',
      amountVnd: 5n,
      reference: 'vault-tx-5',
    };
    const first = await p.payout(input);
    const second = await p.payout(input);
    expect(second.outcome).toBe(first.outcome);
    expect(p.callCount('vault-tx-5')).toBe(1);
  });

  it('reports UNKNOWN for a reference it has never seen', async () => {
    expect(await provider().getStatus('never-sent')).toBe('UNKNOWN');
  });
});
