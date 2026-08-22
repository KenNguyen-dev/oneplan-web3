import { SubscriptionStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { EntitlementService } from '../entitlement/entitlement.service';
import { StoreEventProcessor } from './store-event.processor';
import { StoreEvent } from './store-event.types';

const makePrismaMock = () =>
  ({
    storeNotification: {
      findUnique: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockResolvedValue({ id: 1 }),
      update: jest.fn().mockResolvedValue({}),
      findMany: jest.fn().mockResolvedValue([]),
    },
    subscriptionTransaction: {
      findFirst: jest.fn().mockResolvedValue({ userId: 7 }),
    },
  }) as unknown as PrismaService;

const makeEntitlementMock = () =>
  ({
    apply: jest.fn().mockResolvedValue(undefined),
  }) as unknown as EntitlementService;

const notifEvent = (over: Partial<StoreEvent> = {}): StoreEvent => ({
  store: 'APPLE',
  source: 'NOTIFICATION',
  eventId: 'uuid-1',
  kind: 'SUBSCRIPTION_STATE',
  lineId: 'orig-1',
  transactionId: 'txn-1',
  productId: 'pro_monthly',
  status: SubscriptionStatus.ACTIVE,
  environment: 'Production',
  ...over,
});

describe('StoreEventProcessor', () => {
  let prisma: PrismaService;
  let entitlement: EntitlementService;
  let processor: StoreEventProcessor;

  beforeEach(() => {
    prisma = makePrismaMock();
    entitlement = makeEntitlementMock();
    processor = new StoreEventProcessor(prisma, entitlement);
  });

  it('skips an already-processed event (duplicate eventId) and does NOT call entitlement', async () => {
    (prisma.storeNotification.findUnique as jest.Mock).mockResolvedValue({
      id: 1,
      outcome: 'PROCESSED',
    });
    const outcome = await processor.process(notifEvent());
    expect(outcome).toBe('DUPLICATE');
    expect(entitlement.apply).not.toHaveBeenCalled();
  });

  it('persists ORPHANED when the user cannot be resolved, does NOT throw', async () => {
    (prisma.subscriptionTransaction.findFirst as jest.Mock).mockResolvedValue(
      null,
    );
    const outcome = await processor.process(notifEvent());
    expect(outcome).toBe('ORPHANED');
    expect(entitlement.apply).not.toHaveBeenCalled();
    expect(prisma.storeNotification.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ outcome: 'ORPHANED', userId: null }),
      }),
    );
  });

  it('resolves the user, calls entitlement, marks PROCESSED', async () => {
    const outcome = await processor.process(notifEvent());
    expect(outcome).toBe('PROCESSED');
    expect(entitlement.apply).toHaveBeenCalledWith(
      expect.objectContaining({ userId: 7 }),
    );
  });

  it('source=CLIENT_VERIFY does NOT write to StoreNotification', async () => {
    const outcome = await processor.process(
      notifEvent({ source: 'CLIENT_VERIFY', eventId: undefined, userId: 7 }),
    );
    expect(outcome).toBe('PROCESSED');
    expect(prisma.storeNotification.create).not.toHaveBeenCalled();
    expect(entitlement.apply).toHaveBeenCalled();
  });

  it('kind=TEST returns PROCESSED without touching entitlement', async () => {
    const outcome = await processor.process(notifEvent({ kind: 'TEST' }));
    expect(outcome).toBe('PROCESSED');
    expect(entitlement.apply).not.toHaveBeenCalled();
  });

  describe('replayOrphans', () => {
    it('replays ORPHANED rows sharing a lineId and marks them PROCESSED', async () => {
      (prisma.storeNotification.findMany as jest.Mock).mockResolvedValue([
        {
          id: 11,
          notificationUUID: 'uuid-orphan',
          notificationType: 'REFUND',
          originalTransactionId: 'orig-1',
          transactionId: 'txn-9',
          environment: 'Production',
          store: 'GOOGLE',
          rawPayload: null,
        },
      ]);

      const count = await processor.replayOrphans('orig-1', 7);

      expect(count).toBe(1);
      expect(entitlement.apply).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 7, lineId: 'orig-1' }),
      );
      expect(prisma.storeNotification.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 11 },
          data: expect.objectContaining({ outcome: 'PROCESSED', userId: 7 }),
        }),
      );
    });

    it('returns 0 when there are no ORPHANED rows', async () => {
      (prisma.storeNotification.findMany as jest.Mock).mockResolvedValue([]);
      await expect(processor.replayOrphans('orig-1', 7)).resolves.toBe(0);
      expect(entitlement.apply).not.toHaveBeenCalled();
    });

    it('one failing row does not block the rest', async () => {
      (prisma.storeNotification.findMany as jest.Mock).mockResolvedValue([
        {
          id: 1,
          notificationUUID: 'a',
          originalTransactionId: 'orig-1',
          transactionId: 't1',
          environment: 'Production',
          store: 'APPLE',
          rawPayload: null,
        },
        {
          id: 2,
          notificationUUID: 'b',
          originalTransactionId: 'orig-1',
          transactionId: 't2',
          environment: 'Production',
          store: 'APPLE',
          rawPayload: null,
        },
      ]);
      (entitlement.apply as jest.Mock)
        .mockRejectedValueOnce(new Error('boom'))
        .mockResolvedValueOnce(undefined);

      const count = await processor.replayOrphans('orig-1', 7);
      expect(count).toBe(1);
    });
  });
});
