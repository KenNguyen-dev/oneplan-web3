import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { EntitlementService } from '../entitlement/entitlement.service';
import { StoreEvent } from './store-event.types';

export type ProcessOutcome = 'PROCESSED' | 'DUPLICATE' | 'ORPHANED' | 'FAILED';

@Injectable()
export class StoreEventProcessor {
  private readonly logger = new Logger(StoreEventProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlement: EntitlementService,
  ) {}

  async process(event: StoreEvent): Promise<ProcessOutcome> {
    const isNotification = event.source === 'NOTIFICATION';

    if (isNotification && event.eventId) {
      const existing = await this.prisma.storeNotification.findUnique({
        where: { notificationUUID: event.eventId },
      });
      if (existing) return 'DUPLICATE';
    }

    if (event.kind === 'TEST') {
      if (isNotification) await this.persist(event, null, 'PROCESSED');
      return 'PROCESSED';
    }

    const userId = event.userId ?? (await this.resolveUserId(event));

    if (!userId) {
      // An anticipated race (spec 7.3): the RTDN/ASSN arrives BEFORE the
      // client gets a chance to call verify, so there's no ledger row yet to
      // look up. Keep it — Task 6's replay will pick it up once the client
      // verify comes in.
      if (isNotification) await this.persist(event, null, 'ORPHANED');
      this.logger.warn(
        `StoreEvent orphaned: store=${event.store} line=${event.lineId} txn=${event.transactionId}`,
      );
      return 'ORPHANED';
    }

    try {
      await this.entitlement.apply({ ...event, userId });
    } catch (error) {
      this.logger.error('EntitlementService.apply failed', error);
      if (isNotification) await this.persist(event, userId, 'FAILED', error);
      throw error;
    }

    if (isNotification) await this.persist(event, userId, 'PROCESSED');
    return 'PROCESSED';
  }

  /**
   * Replays notifications that were previously ORPHANED for the same lineId,
   * now that we know who the user is (typically right after client verify
   * comes in).
   *
   * Safe to re-run: each row is just a "doorbell" — apply() uses already
   * normalized data, and the ledger/grant writes are all idempotent.
   *
   * One failing row must NOT block the rest: they're independent of each
   * other, and a broken payload shouldn't hold a valid refund hostage.
   */
  async replayOrphans(lineId: string, userId?: number): Promise<number> {
    const orphans = await this.prisma.storeNotification.findMany({
      where: { originalTransactionId: lineId, outcome: 'ORPHANED' },
      orderBy: { id: 'asc' },
    });
    if (orphans.length === 0) return 0;

    let replayed = 0;
    for (const row of orphans) {
      try {
        await this.entitlement.apply({
          store: (row.store as StoreEvent['store']) ?? 'APPLE',
          source: 'NOTIFICATION',
          eventId: row.notificationUUID,
          kind: this.inferKind(row.notificationType),
          lineId,
          transactionId: row.transactionId ?? '',
          productId: '',
          userId: userId ?? row.userId ?? undefined,
          environment:
            (row.environment as StoreEvent['environment']) ?? 'Production',
          notificationType: row.notificationType,
          raw: row.rawPayload,
        });
        await this.prisma.storeNotification.update({
          where: { id: row.id },
          data: { outcome: 'PROCESSED', userId, processedAt: new Date() },
        });
        replayed += 1;
      } catch (error) {
        this.logger.error(
          `Replay orphan ${row.id} failed — leaving it ORPHANED for next time`,
          error,
        );
      }
    }
    return replayed;
  }

  private inferKind(notificationType: string | null): StoreEvent['kind'] {
    if (!notificationType) return 'SUBSCRIPTION_STATE';
    const t = notificationType.toUpperCase();
    if (t.includes('REFUND') || t.includes('REVOKE') || t.includes('VOIDED')) {
      return 'REFUND';
    }
    return 'SUBSCRIPTION_STATE';
  }

  /** Looks up the user via an existing ledger row. Apple: originalTransactionId. Play: purchaseToken stored in transactionId. */
  private async resolveUserId(event: StoreEvent): Promise<number | null> {
    const row = await this.prisma.subscriptionTransaction.findFirst({
      where: {
        OR: [
          { transactionId: event.transactionId },
          { originalTransactionId: event.lineId },
        ],
      },
      select: { userId: true },
    });
    return row?.userId ?? null;
  }

  private async persist(
    event: StoreEvent,
    userId: number | null,
    outcome: ProcessOutcome,
    error?: unknown,
  ): Promise<void> {
    if (!event.eventId) return;
    await this.prisma.storeNotification.create({
      data: {
        notificationUUID: event.eventId,
        notificationType: event.notificationType ?? null,
        originalTransactionId: event.lineId,
        transactionId: event.transactionId,
        environment: event.environment,
        signedDate: event.signedDate ?? null,
        store: event.store,
        rawPayload: (event.raw ?? null) as never,
        userId,
        outcome,
        errorMessage:
          error instanceof Error ? error.message.slice(0, 255) : null,
        processedAt: outcome === 'PROCESSED' ? new Date() : null,
      },
    });
  }
}
