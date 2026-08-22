import { TelegramCodeService } from './telegram-code.service';
import { PrismaService } from '../prisma/prisma.service';

type TxClient = {
  $executeRaw: jest.Mock;
  $queryRaw: jest.Mock;
  telegramOfferCode: { findFirst: jest.Mock };
};

function createTx(): TxClient {
  return {
    $executeRaw: jest.fn().mockResolvedValue(0),
    $queryRaw: jest.fn(),
    telegramOfferCode: { findFirst: jest.fn() },
  };
}

function createService(tx: TxClient) {
  const prisma = {
    telegramOfferCode: {
      createMany: jest.fn(),
      findMany: jest.fn(),
      count: jest.fn(),
      groupBy: jest.fn(),
    },
    $transaction: jest.fn((cb: (t: TxClient) => unknown) => cb(tx)),
    $queryRaw: jest.fn(),
  };
  const service = new TelegramCodeService(prisma as unknown as PrismaService);
  return { service, prisma };
}

describe('TelegramCodeService', () => {
  describe('uploadCodes', () => {
    it('de-dupes within the request and reports inserted/skipped', async () => {
      const tx = createTx();
      const { service, prisma } = createService(tx);
      // 3 unique after trim/dedupe ("A" twice, " B ", "C"); DB skips 1 existing.
      prisma.telegramOfferCode.createMany.mockResolvedValue({ count: 2 });

      const res = await service.uploadCodes(['A', 'A', ' B ', 'C']);

      // cleaned set = {A, B, C}
      expect(prisma.telegramOfferCode.createMany).toHaveBeenCalledWith({
        data: [
          { code: 'A', batchLabel: null },
          { code: 'B', batchLabel: null },
          { code: 'C', batchLabel: null },
        ],
        skipDuplicates: true,
      });
      // 4 submitted, 2 actually inserted → 2 skipped.
      expect(res).toEqual({ inserted: 2, skipped: 2 });
    });

    it('returns early when nothing is left after cleaning', async () => {
      const tx = createTx();
      const { service, prisma } = createService(tx);

      const res = await service.uploadCodes(['', '   ']);

      expect(prisma.telegramOfferCode.createMany).not.toHaveBeenCalled();
      expect(res).toEqual({ inserted: 0, skipped: 2 });
    });
  });

  describe('claimCode', () => {
    it('takes the per-user advisory lock', async () => {
      const tx = createTx();
      tx.telegramOfferCode.findFirst.mockResolvedValue({ code: 'X' });
      const { service } = createService(tx);

      await service.claimCode(123n);

      expect(tx.$executeRaw).toHaveBeenCalled();
    });

    it('returns the existing code (reused) for a user who already claimed', async () => {
      const tx = createTx();
      tx.telegramOfferCode.findFirst.mockResolvedValue({ code: 'EXISTING' });
      const { service } = createService(tx);

      const res = await service.claimCode(123n, 'alice');

      expect(res).toEqual({ code: 'EXISTING', reused: true });
      // No free-row pick when the user already has one.
      expect(tx.$queryRaw).not.toHaveBeenCalled();
    });

    it('assigns a fresh code when the user has none and the pool has stock', async () => {
      const tx = createTx();
      tx.telegramOfferCode.findFirst.mockResolvedValue(null);
      tx.$queryRaw.mockResolvedValue([{ code: 'FRESH' }]);
      const { service } = createService(tx);

      const res = await service.claimCode(456n, 'bob');

      expect(res).toEqual({ code: 'FRESH', reused: false });
      expect(tx.$queryRaw).toHaveBeenCalledTimes(1);
    });

    it('reports exhausted when the pool is empty', async () => {
      const tx = createTx();
      tx.telegramOfferCode.findFirst.mockResolvedValue(null);
      tx.$queryRaw.mockResolvedValue([]);
      const { service } = createService(tx);

      const res = await service.claimCode(789n);

      expect(res).toEqual({ exhausted: true });
    });
  });
});
