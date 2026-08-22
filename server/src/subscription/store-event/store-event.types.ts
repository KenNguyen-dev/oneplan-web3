import { SubscriptionStatus } from '@prisma/client';

export type StoreKind = 'APPLE' | 'GOOGLE';

/**
 * NOTIFICATION = the store pushes to us (ASSN, RTDN). Has a dedup key at the
 * transport layer, and IS recorded into StoreNotification.
 * CLIENT_VERIFY = we proactively query the store because the client just
 * called in. No transport-level dedup key, NOT recorded into
 * StoreNotification (dedup instead relies on the existing
 * SubscriptionTransaction.transactionId @unique).
 */
export type StoreEventSource = 'NOTIFICATION' | 'CLIENT_VERIFY';

export type StoreEventKind =
  | 'SUBSCRIPTION_STATE'
  | 'ONE_TIME_PURCHASE'
  | 'REFUND'
  | 'TEST';

export interface StoreEvent {
  store: StoreKind;
  source: StoreEventSource;
  /** Only present when source === 'NOTIFICATION'. Apple: notificationUUID. Play: Pub/Sub messageId. */
  eventId?: string;
  kind: StoreEventKind;
  /** Stable identifier for the subscription line. Apple: originalTransactionId. Play: root token of the linkedPurchaseToken chain. */
  lineId: string;
  transactionId: string;
  productId: string;
  userId?: number;
  status?: SubscriptionStatus;
  expiresAt?: Date | null;
  purchasedAt?: Date | null;
  revokedAt?: Date | null;
  environment: 'Production' | 'Sandbox' | 'Test';
  notificationType?: string | null;
  signedDate?: Date | null;
  raw?: unknown;
}
