import { Injectable } from '@nestjs/common';
import { TripStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ENGAGEMENT_CAP_WINDOW_MS } from './engagement-frequency.service';
import { UserEngagementContext } from './engagement.types';

const PAGE_SIZE = 500;

/**
 * Finds candidate users and loads their per-user context in batch (no N+1).
 *
 * A candidate is a user who:
 *  - has opted in (engagementPushEnabled) AND given marketing consent
 *    (engagementConsentedAt — App Store 4.5.4), AND
 *  - has at least one device token, AND
 *  - has NOT received an engagement push in the last 24h (the cadence cap).
 *
 * The batch is frozen against mid-pagination inserts via `createdAt < cronStart`
 * and ordered by `id` so cursor pagination cannot skip/duplicate users.
 */
@Injectable()
export class EngagementTargetingService {
  constructor(private readonly prisma: PrismaService) {}

  /** One page of candidate user contexts after `afterId` (exclusive). */
  async loadCandidatePage(
    cronStart: Date,
    afterId: number,
  ): Promise<UserEngagementContext[]> {
    const cutoff = new Date(cronStart.getTime() - ENGAGEMENT_CAP_WINDOW_MS);

    const users = await this.prisma.user.findMany({
      where: {
        id: { gt: afterId },
        createdAt: { lt: cronStart },
        engagementPushEnabled: true,
        engagementConsentedAt: { not: null },
        deviceTokens: { some: {} },
        engagementNotifications: { none: { sentAt: { gte: cutoff } } },
      },
      orderBy: { id: 'asc' },
      take: PAGE_SIZE,
      select: {
        id: true,
        locale: true,
        analyticsSessions: {
          orderBy: { startedAt: 'desc' },
          take: 1,
          select: { startedAt: true },
        },
        createdTrips: {
          where: { status: { not: TripStatus.ENDED } },
          select: {
            id: true,
            status: true,
            name: true,
            cityId: true,
            countryId: true,
            city: { select: { name: true } },
            country: { select: { timezones: true } },
            createdAt: true,
            _count: { select: { planItems: true } },
          },
        },
      },
    });

    return users.map((u) => ({
      userId: u.id,
      locale: u.locale,
      lastSessionAt: u.analyticsSessions[0]?.startedAt ?? null,
      trips: u.createdTrips.map((t) => ({
        id: t.id,
        status: t.status,
        name: t.name,
        cityId: t.cityId,
        cityName: t.city?.name ?? null,
        countryId: t.countryId,
        countryTimezones: t.country?.timezones ?? null,
        planItemCount: t._count.planItems,
        createdAt: t.createdAt,
      })),
    }));
  }
}
