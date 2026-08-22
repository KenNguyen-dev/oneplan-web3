import { Injectable } from '@nestjs/common';
import { JWSTransactionDecodedPayload } from '@apple/app-store-server-library';
import { SubscriptionStatus } from '@prisma/client';
import { StoreEvent, StoreEventSource } from '../store-event/store-event.types';

export interface AppleEventInput {
  transaction: JWSTransactionDecodedPayload;
  source: StoreEventSource;
  notificationUUID?: string;
  notificationType?: string;
  signedDate?: Date;
  status?: SubscriptionStatus;
  isCreditProduct: boolean;
  raw?: unknown;
  /**
   * Pass this when the caller ALREADY knows the user (CLIENT_VERIFY always does;
   * handleWebhook knows it after looking up originalTransactionId). When this is
   * set, StoreEventProcessor skips resolveUserId — no longer depending on a
   * pre-existing SubscriptionTransaction row. Leave it empty for a truly
   * anonymous NOTIFICATION (spec 7.3) — resolveUserId + ORPHANED + replayOrphans
   * is still the only path for that case.
   */
  userId?: number;
}

/**
 * Translates the Apple format into a StoreEvent. Must NOT know about Prisma or
 * entitlement — if this file ever needs to import PrismaService, the boundary
 * is broken.
 */
@Injectable()
export class AppleStoreAdapter {
  toStoreEvent(input: AppleEventInput): StoreEvent {
    const t = input.transaction;
    const isRefund = Boolean(t.revocationDate);
    const kind: StoreEvent['kind'] = isRefund
      ? 'REFUND'
      : input.isCreditProduct
        ? 'ONE_TIME_PURCHASE'
        : 'SUBSCRIPTION_STATE';

    return {
      store: 'APPLE',
      source: input.source,
      eventId: input.notificationUUID,
      kind,
      lineId: t.originalTransactionId ?? t.transactionId ?? '',
      transactionId: t.transactionId ?? '',
      productId: t.productId ?? '',
      userId: input.userId,
      status: kind === 'SUBSCRIPTION_STATE' ? input.status : undefined,
      expiresAt: t.expiresDate ? new Date(t.expiresDate) : null,
      purchasedAt: t.purchaseDate ? new Date(t.purchaseDate) : null,
      revokedAt: t.revocationDate ? new Date(t.revocationDate) : null,
      environment: t.environment === 'Production' ? 'Production' : 'Sandbox',
      notificationType: input.notificationType ?? null,
      signedDate: input.signedDate ?? null,
      raw: input.raw,
    };
  }
}
