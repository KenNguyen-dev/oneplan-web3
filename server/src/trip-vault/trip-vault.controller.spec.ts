import { TripVaultController } from './trip-vault.controller';

function deps() {
  return {
    vaultService: {
      linkWallet: jest.fn().mockResolvedValue({ publicKey: 'PK' }),
      requireVault: jest.fn().mockResolvedValue({
        vaultPda: 'VaultPda',
        thresholdMicro: 10_000_000n,
        dailyLimitMicro: 50_000_000n,
      }),
      getBalance: jest.fn().mockResolvedValue({
        balanceMicro: 1_234_567n,
        vaultPda: 'VaultPda',
      }),
      buildDepositTx: jest.fn().mockResolvedValue('base64tx'),
      syncMembers: jest.fn().mockResolvedValue(2),
    },
    payService: {
      quote: jest.fn().mockResolvedValue({
        recipientName: 'NGUYEN VAN A',
        bankBin: '970412',
        accountNumber: '109000636588',
        amountVnd: 200_000n,
        amountUsdcMicro: 7_660_000n,
        feeMicro: 57_450n,
        rate: '26500',
        needsApproval: false,
        description: null,
      }),
      preparePayment: jest.fn(),
      submitPayment: jest.fn(),
      buildApprovalTx: jest.fn(),
    },
    historyService: {
      getHistory: jest.fn().mockResolvedValue([]),
      getTransactionDetail: jest.fn(),
    },
    settlementService: {
      preview: jest.fn(),
      confirmCashDebt: jest.fn(),
      executeFromServer: jest.fn(),
    },
  };
}

const USER_ID = 7;

function build(d: ReturnType<typeof deps>): TripVaultController {
  return new TripVaultController(
    d.vaultService as never,
    d.payService as never,
    d.historyService as never,
    d.settlementService as never,
  );
}

describe('TripVaultController', () => {
  it('serialises balances as decimal strings, never numbers', async () => {
    const result = await build(deps()).getBalance(42);

    expect(result.balanceMicro).toBe('1234567');
    expect(typeof result.balanceMicro).toBe('string');
    expect(typeof result.thresholdMicro).toBe('string');
    expect(typeof result.dailyLimitMicro).toBe('string');
  });

  it('serialises quote amounts as decimal strings', async () => {
    const result = await build(deps()).quote(42, { qrPayload: 'x' }, USER_ID);

    expect(result.amountVnd).toBe('200000');
    expect(result.amountUsdcMicro).toBe('7660000');
    expect(result.feeMicro).toBe('57450');
    expect(result.needsApproval).toBe(false);
  });

  it('passes an amount override through as a bigint', async () => {
    const d = deps();
    await build(d).quote(42, { qrPayload: 'x', amountVnd: '350000' }, USER_ID);

    expect(d.payService.quote).toHaveBeenCalledWith(42, 7, 'x', 350_000n);
  });

  it('passes a deposit amount through as a bigint', async () => {
    const d = deps();
    await build(d).deposit(42, { amountMicro: '5000000' }, USER_ID);

    expect(d.vaultService.buildDepositTx).toHaveBeenCalledWith(
      42,
      7,
      5_000_000n,
    );
  });
});
