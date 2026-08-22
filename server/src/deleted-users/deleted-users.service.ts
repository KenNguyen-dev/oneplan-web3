import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  DeletedUserArchiveDto,
  DeletedUserSummaryDto,
} from './dto/deleted-user.dto';

// How long an identified snapshot of a deleted account is kept before the cron
// purges it. Deliberately short and enforced automatically.
export const DELETED_USER_RETENTION_DAYS = 30;

const DAY_MS = 24 * 60 * 60 * 1000;
// Bound the snapshot so one heavy account cannot write a huge JSON blob.
const MAX_ROWS_PER_SECTION = 200;

@Injectable()
export class DeletedUsersService {
  private readonly logger = new Logger(DeletedUsersService.name);

  constructor(private readonly prisma: PrismaService) {}

  // Snapshot everything we know about the user and store it, BEFORE the caller
  // deletes the account. Must run inside the delete transaction so the archive
  // and the deletion commit together.
  async archiveUser(
    tx: Prisma.TransactionClient,
    userId: number,
  ): Promise<void> {
    const user = await tx.user.findUnique({ where: { id: userId } });
    if (!user) return;

    const [
      authAccounts,
      createdTrips,
      tripMemberships,
      expenses,
      subscriptionTransactions,
      scanGrants,
      giftsReceived,
      listings,
      boardCount,
      photoCount,
      noteCount,
      friendCount,
      eventCount,
      sessionCount,
      firstEvent,
      lastEvent,
      eventsByName,
    ] = await Promise.all([
      tx.authAccount.findMany({
        where: { userId },
        select: { provider: true, providerUserId: true, createdAt: true },
      }),
      tx.trip.findMany({
        where: { createdById: userId },
        select: {
          id: true,
          name: true,
          startDate: true,
          endDate: true,
          status: true,
          currency: true,
          createdAt: true,
        },
        take: MAX_ROWS_PER_SECTION,
      }),
      tx.tripMember.findMany({
        where: { userId },
        select: { tripId: true, inviteStatus: true, joinedAt: true },
        take: MAX_ROWS_PER_SECTION,
      }),
      tx.expense.findMany({
        where: { paidById: userId },
        select: {
          id: true,
          tripId: true,
          name: true,
          amount: true,
          category: true,
          originalCurrency: true,
          expenseDate: true,
          createdAt: true,
        },
        take: MAX_ROWS_PER_SECTION,
      }),
      tx.subscriptionTransaction.findMany({
        where: { userId },
        take: MAX_ROWS_PER_SECTION,
      }),
      tx.scanCreditGrant.findMany({
        where: { userId },
        take: MAX_ROWS_PER_SECTION,
      }),
      tx.giftLog.findMany({
        where: { recipientUserId: userId },
        take: MAX_ROWS_PER_SECTION,
      }),
      tx.marketplaceListing.findMany({
        where: { createdById: userId },
        select: {
          id: true,
          publicId: true,
          name: true,
          status: true,
          price: true,
          currency: true,
          createdAt: true,
        },
        take: MAX_ROWS_PER_SECTION,
      }),
      tx.board.count({ where: { userId } }),
      tx.tripPhoto.count({ where: { uploadedById: userId } }),
      tx.tripNote.count({ where: { createdById: userId } }),
      tx.friendship.count({ where: { userAId: userId } }),
      tx.analyticsEvent.count({ where: { userId } }),
      tx.analyticsSession.count({ where: { userId } }),
      tx.analyticsEvent.findFirst({
        where: { userId },
        orderBy: { occurredAt: 'asc' },
        select: { occurredAt: true },
      }),
      tx.analyticsEvent.findFirst({
        where: { userId },
        orderBy: { occurredAt: 'desc' },
        select: { occurredAt: true },
      }),
      tx.analyticsEvent.groupBy({
        by: ['eventName'],
        where: { userId },
        _count: true,
      }),
    ]);

    const snapshot = {
      profile: {
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
        friendCode: user.friendCode,
        locale: user.locale,
        preferredCurrency: user.preferredCurrency,
        createdAt: user.createdAt.toISOString(),
        engagementPushEnabled: user.engagementPushEnabled,
        engagementConsentedAt:
          user.engagementConsentedAt?.toISOString() ?? null,
      },
      subscription: {
        status: user.subscriptionStatus,
        productId: user.subscriptionProductId,
        expiresAt: user.subscriptionExpiresAt?.toISOString() ?? null,
        autoRenewEnabled: user.autoRenewEnabled,
        originalTransactionId: user.originalTransactionId,
        transactions: subscriptionTransactions,
      },
      authProviders: authAccounts,
      trips: { created: createdTrips, memberships: tripMemberships },
      expenses,
      marketplaceListings: listings,
      scanCredits: {
        grants: scanGrants,
        totalGranted: scanGrants.reduce((s, g) => s + g.amount, 0),
        remaining: scanGrants.reduce((s, g) => s + g.remaining, 0),
      },
      giftsReceived,
      counts: {
        boards: boardCount,
        tripPhotos: photoCount,
        tripNotes: noteCount,
        friendships: friendCount,
      },
      // Identified activity summary. The raw analytics rows themselves stay in
      // place, anonymized (user_id -> NULL), as before.
      activity: {
        totalEvents: eventCount,
        totalSessions: sessionCount,
        firstEventAt: firstEvent?.occurredAt.toISOString() ?? null,
        lastEventAt: lastEvent?.occurredAt.toISOString() ?? null,
        eventsByName: eventsByName.map((e) => ({
          name: e.eventName,
          count: e._count,
        })),
      },
    };

    await tx.deletedUserArchive.create({
      data: {
        originalUserId: user.id,
        email: user.email,
        displayName: user.displayName,
        // Decimal/Date values are serialized to JSON-safe primitives.
        snapshot: JSON.parse(JSON.stringify(snapshot)) as Prisma.InputJsonValue,
      },
    });

    this.logger.log(`Archived deleted account ${user.id} (${user.email})`);
  }

  async list(limit = 100): Promise<DeletedUserSummaryDto[]> {
    const rows = await this.prisma.deletedUserArchive.findMany({
      orderBy: { deletedAt: 'desc' },
      take: Math.min(Math.max(limit, 1), 500),
      select: {
        id: true,
        originalUserId: true,
        email: true,
        displayName: true,
        deletedAt: true,
      },
    });
    return rows.map((r) => ({
      id: r.id,
      originalUserId: r.originalUserId,
      email: r.email,
      displayName: r.displayName,
      deletedAt: r.deletedAt.toISOString(),
      purgeAt: this.purgeAt(r.deletedAt).toISOString(),
      daysLeft: this.daysLeft(r.deletedAt),
    }));
  }

  async get(id: number): Promise<DeletedUserArchiveDto> {
    const row = await this.prisma.deletedUserArchive.findUnique({
      where: { id },
    });
    if (!row) throw new NotFoundException('Deleted user archive not found');
    return {
      id: row.id,
      originalUserId: row.originalUserId,
      email: row.email,
      displayName: row.displayName,
      deletedAt: row.deletedAt.toISOString(),
      purgeAt: this.purgeAt(row.deletedAt).toISOString(),
      daysLeft: this.daysLeft(row.deletedAt),
      snapshot: row.snapshot,
    };
  }

  private purgeAt(deletedAt: Date): Date {
    return new Date(deletedAt.getTime() + DELETED_USER_RETENTION_DAYS * DAY_MS);
  }

  private daysLeft(deletedAt: Date): number {
    const ms = this.purgeAt(deletedAt).getTime() - Date.now();
    return Math.max(0, Math.ceil(ms / DAY_MS));
  }

  // Enforces the retention window: anything older than the limit is deleted for
  // good. Without this the archive would silently become permanent storage.
  @Cron(CronExpression.EVERY_HOUR)
  async purgeExpired(): Promise<void> {
    const cutoff = new Date(Date.now() - DELETED_USER_RETENTION_DAYS * DAY_MS);
    try {
      const { count } = await this.prisma.deletedUserArchive.deleteMany({
        where: { deletedAt: { lt: cutoff } },
      });
      if (count > 0) {
        this.logger.log(
          `Purged ${count} deleted-user archive(s) older than ${DELETED_USER_RETENTION_DAYS} days`,
        );
      }
    } catch (e) {
      this.logger.error(
        `Failed to purge deleted-user archives: ${e instanceof Error ? e.message : String(e)}`,
      );
    }
  }
}
