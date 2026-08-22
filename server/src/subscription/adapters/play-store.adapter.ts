import { Injectable, Logger } from '@nestjs/common';
import { SubscriptionStatus } from '@prisma/client';
import { StoreEvent, StoreEventSource } from '../store-event/store-event.types';
import { ConfigService } from '@nestjs/config';

export interface PlayVerifiedPurchase {
  kind: 'subscription' | 'product';
  productId: string;
  purchaseToken: string;
  expiresAt?: Date | null;
  startedAt?: Date | null;
  revoked: boolean;
  isTest?: boolean;
}

export interface PlayEventInput {
  verified: PlayVerifiedPurchase;
  source: StoreEventSource;
  userId?: number;
  status?: SubscriptionStatus;
  isCreditProduct: boolean;
  eventId?: string;
  raw?: unknown;
  linkedPurchaseToken?: string;
}

// RTDN format references:
// https://developer.android.com/google/play/billing/rtdn-reference

export interface DeveloperNotification {
  version: string;
  packageName: string;
  eventTimeMillis: string;
  subscriptionNotification?: SubscriptionNotification;
  oneTimeProductNotification?: OneTimeProductNotification;
  voidedPurchaseNotification?: VoidedPurchaseNotification;
  testNotification?: TestNotification;
}

export interface SubscriptionNotification {
  version: string;
  notificationType: number;
  purchaseToken: string;
  subscriptionId?: string; // It seems subscriptionId is no longer strictly returned in the latest schema at the top level of this object (it relies on DeveloperNotification logic or checking via API), or it might still be there for some versions. Let's make it optional.
}

export interface OneTimeProductNotification {
  version: string;
  notificationType: number;
  purchaseToken: string;
  sku: string;
}

export interface VoidedPurchaseNotification {
  purchaseToken: string;
  orderId: string;
  productType: number; // 1 = inapp, 2 = subs
  refundType: number; // 1 = user requested, 2 = dev requested
}

export interface TestNotification {
  version: string;
}

/**
 * Translates verified Google Play purchase data or DeveloperNotification RTDNs into a StoreEvent.
 * Must NOT know about Prisma.
 */
@Injectable()
export class PlayStoreAdapter {
  private readonly logger = new Logger(PlayStoreAdapter.name);

  constructor(private readonly configService: ConfigService) {}

  toStoreEvent(input: PlayEventInput): StoreEvent {
    const v = input.verified;
    const kind: StoreEvent['kind'] = v.revoked
      ? 'REFUND'
      : input.isCreditProduct
        ? 'ONE_TIME_PURCHASE'
        : 'SUBSCRIPTION_STATE';

    return {
      store: 'GOOGLE',
      source: input.source,
      eventId: input.eventId,
      kind,
      // If there's a linkedPurchaseToken (an upgrade/downgrade), the older token is the "lineId" we trace
      lineId: input.linkedPurchaseToken ?? v.purchaseToken,
      transactionId: v.purchaseToken,
      productId: v.productId,
      userId: input.userId,
      status: kind === 'SUBSCRIPTION_STATE' ? input.status : undefined,
      expiresAt: v.expiresAt ?? null,
      purchasedAt: v.startedAt ?? null,
      revokedAt: v.revoked ? new Date() : null,
      environment: v.isTest ? 'Test' : 'Production',
      raw: input.raw,
    };
  }

  parseDeveloperNotification(base64Data: string): DeveloperNotification | null {
    try {
      const jsonStr = Buffer.from(base64Data, 'base64').toString('utf8');
      return JSON.parse(jsonStr) as DeveloperNotification;
    } catch (error) {
      this.logger.error('Failed to parse RTDN data', error);
      return null;
    }
  }

  /**
   * If the notification is a Refund (VoidedPurchaseNotification), or an expiry,
   * we must derive a StoreEvent directly because the Play API might return
   * 404 or missing active status for voided tokens. For refunds we only need
   * the token to perform the revocation.
   */
  createRefundEventFromNotification(
    notification: DeveloperNotification,
    eventId: string,
    isCreditProduct: boolean,
  ): StoreEvent | null {
    if (notification.voidedPurchaseNotification) {
      return {
        store: 'GOOGLE',
        source: 'NOTIFICATION',
        eventId,
        kind: 'REFUND',
        lineId: notification.voidedPurchaseNotification.purchaseToken,
        transactionId: notification.voidedPurchaseNotification.purchaseToken,
        // The VoidedPurchaseNotification does not include the exact productId (only orderId),
        // but our scanner only needs the token and transaction ID.
        productId: '', 
        userId: undefined,
        revokedAt: new Date(Number(notification.eventTimeMillis)),
        environment: 'Production', // Typically production
        raw: notification,
      };
    }
    return null;
  }
}
