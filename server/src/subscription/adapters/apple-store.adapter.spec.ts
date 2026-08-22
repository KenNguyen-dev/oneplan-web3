import { SubscriptionStatus } from '@prisma/client';
import { AppleStoreAdapter } from './apple-store.adapter';

const txn = (over: Record<string, unknown> = {}) =>
  ({
    transactionId: 'txn-1',
    originalTransactionId: 'orig-1',
    productId: 'pro_monthly',
    environment: 'Production',
    purchaseDate: 1750000000000,
    expiresDate: 1780000000000,
    ...over,
  }) as never;

describe('AppleStoreAdapter', () => {
  const adapter = new AppleStoreAdapter();

  it('maps subscription to SUBSCRIPTION_STATE with lineId = originalTransactionId', () => {
    const e = adapter.toStoreEvent({
      transaction: txn(),
      source: 'CLIENT_VERIFY',
      status: SubscriptionStatus.ACTIVE,
      isCreditProduct: false,
    });
    expect(e.store).toBe('APPLE');
    expect(e.kind).toBe('SUBSCRIPTION_STATE');
    expect(e.lineId).toBe('orig-1');
    expect(e.expiresAt).toEqual(new Date(1780000000000));
  });

  it('maps credit product to ONE_TIME_PURCHASE without a status', () => {
    const e = adapter.toStoreEvent({
      transaction: txn({
        productId: 'oneplan.video_scan_5',
        expiresDate: undefined,
      }),
      source: 'CLIENT_VERIFY',
      isCreditProduct: true,
    });
    expect(e.kind).toBe('ONE_TIME_PURCHASE');
    expect(e.status).toBeUndefined();
  });

  it('maps revocationDate to REFUND', () => {
    const e = adapter.toStoreEvent({
      transaction: txn({ revocationDate: 1760000000000 }),
      source: 'NOTIFICATION',
      notificationUUID: 'uuid-1',
      notificationType: 'REFUND',
      isCreditProduct: true,
    });
    expect(e.kind).toBe('REFUND');
    expect(e.eventId).toBe('uuid-1');
  });

  it('normalizes an unrecognized environment to Sandbox', () => {
    const e = adapter.toStoreEvent({
      transaction: txn({ environment: 'Xcode' }),
      source: 'CLIENT_VERIFY',
      isCreditProduct: false,
    });
    expect(e.environment).toBe('Sandbox');
  });

  it('carries a known userId into StoreEvent when the caller passes one (CLIENT_VERIFY / already-resolved user)', () => {
    const e = adapter.toStoreEvent({
      transaction: txn(),
      source: 'CLIENT_VERIFY',
      isCreditProduct: false,
      userId: 42,
    });
    expect(e.userId).toBe(42);
  });

  it('leaves userId undefined when the caller does not pass one (anonymous NOTIFICATION — awaiting resolveUserId)', () => {
    const e = adapter.toStoreEvent({
      transaction: txn(),
      source: 'NOTIFICATION',
      notificationUUID: 'uuid-2',
      isCreditProduct: false,
    });
    expect(e.userId).toBeUndefined();
  });
});
