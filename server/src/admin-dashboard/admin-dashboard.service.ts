import { Injectable, NotFoundException } from '@nestjs/common';
import {
  AnalyticsEventName,
  Currency,
  Prisma,
  TripStatus,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AdminUserDetailDto } from './dto/user-detail.dto';
import { AdminTripDetailDto } from './dto/trip-detail.dto';
import {
  AdminAnalyticsEventDto,
  AdminAnalyticsEventListQueryDto,
  AdminAnalyticsEventListResponseDto,
} from './dto/analytics-event-list.dto';
import {
  AdminAnalyticsByDayDto,
  AdminAnalyticsByEventDto,
  AdminAnalyticsByPlatformDto,
  AdminAnalyticsSummaryDto,
  AdminAnalyticsSummaryQueryDto,
} from './dto/analytics-summary.dto';
import {
  AdminSortDir,
  AdminUserListQueryDto,
  AdminUserListResponseDto,
  AdminUserSortBy,
  AdminUserSummaryDto,
} from './dto/user-list.dto';
import {
  AdminCountByDayDto,
  AdminUsersAggregatesDto,
  AdminUsersAggregatesQueryDto,
} from './dto/users-aggregates.dto';
import {
  AdminTripsAggregatesDto,
  AdminTripsAggregatesQueryDto,
} from './dto/trips-aggregates.dto';
import {
  AdminTripListQueryDto,
  AdminTripListResponseDto,
  AdminTripSortBy,
  AdminTripSummaryDto,
} from './dto/trip-list.dto';

const PAY_ONCE_SKU = 'pay_once';

// Auto-renewable Pro SKUs (mirrors PRO_SUBSCRIPTION_SKUS in subscription.service).
// The subscription_transaction table also stores consumable scan-pack and
// pay_once purchases, so subscription metrics must filter to these.
const PRO_SUBSCRIPTION_SKUS = ['pro_weekly', 'pro_monthly', 'pro_yearly'];

const USER_SUMMARY_SELECT = {
  id: true,
  email: true,
  displayName: true,
  avatarUrl: true,
  createdAt: true,
  subscriptionStatus: true,
  subscriptionProductId: true,
  subscriptionExpiresAt: true,
  authAccounts: { select: { provider: true } },
  _count: { select: { tripMembers: true } },
} satisfies Prisma.UserSelect;

const DEFAULT_SUMMARY_WINDOW_DAYS = 30;
const MAX_SUMMARY_WINDOW_DAYS = 365;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

@Injectable()
export class AdminDashboardService {
  constructor(private readonly prisma: PrismaService) {}

  async listUsers(
    query: AdminUserListQueryDto,
  ): Promise<AdminUserListResponseDto> {
    const page = query.page ?? 1;
    const limit = query.limit ?? 25;
    const skip = (page - 1) * limit;
    const sortBy = query.sortBy ?? AdminUserSortBy.createdAt;
    const sortDir = query.sortDir ?? AdminSortDir.desc;

    const where: Prisma.UserWhereInput = query.search
      ? {
          OR: [
            { email: { contains: query.search, mode: 'insensitive' } },
            { displayName: { contains: query.search, mode: 'insensitive' } },
          ],
        }
      : {};

    const total = await this.prisma.user.count({ where });

    // Computed columns (scanCredits, trips) can't be sorted via Prisma orderBy,
    // so they take a raw-SQL path that resolves the ordered page of ids first.
    // Native columns map directly to a Prisma orderBy.
    const orderedIds =
      sortBy === AdminUserSortBy.scanCredits || sortBy === AdminUserSortBy.trips
        ? await this.orderedUserIdsByComputed(
            query.search,
            sortBy,
            sortDir,
            limit,
            skip,
          )
        : null;

    const pageUsers = orderedIds
      ? await this.prisma.user.findMany({
          where: { id: { in: orderedIds } },
          select: USER_SUMMARY_SELECT,
        })
      : await this.prisma.user.findMany({
          where,
          orderBy:
            sortBy === AdminUserSortBy.subscriptionExpiresAt
              ? { subscriptionExpiresAt: sortDir }
              : { createdAt: sortDir },
          skip,
          take: limit,
          select: USER_SUMMARY_SELECT,
        });

    // Raw path returns ids in sorted order; findMany does not preserve it.
    const users = orderedIds
      ? orderedIds
          .map((id) => pageUsers.find((u) => u.id === id))
          .filter((u): u is (typeof pageUsers)[number] => u !== undefined)
      : pageUsers;

    const pageIds = users.map((u) => u.id);
    const grantSums = pageIds.length
      ? await this.prisma.scanCreditGrant.groupBy({
          by: ['userId'],
          where: {
            userId: { in: pageIds },
            OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
          },
          _sum: { remaining: true },
        })
      : [];
    const grantsByUser = new Map<number, number>(
      grantSums.map((row) => [row.userId, row._sum.remaining ?? 0]),
    );

    const items: AdminUserSummaryDto[] = users.map((u) => ({
      id: u.id,
      email: u.email,
      displayName: u.displayName,
      avatarUrl: u.avatarUrl,
      createdAt: u.createdAt,
      authProviders: Array.from(new Set(u.authAccounts.map((a) => a.provider))),
      subscriptionStatus: u.subscriptionStatus,
      subscriptionProductId: u.subscriptionProductId,
      subscriptionExpiresAt: u.subscriptionExpiresAt,
      scanCreditsRemaining: grantsByUser.get(u.id) ?? 0,
      tripCount: u._count.tripMembers,
    }));

    return { items, total, page, limit };
  }

  private async orderedUserIdsByComputed(
    search: string | undefined,
    sortBy: AdminUserSortBy,
    sortDir: AdminSortDir,
    limit: number,
    skip: number,
  ): Promise<number[]> {
    const orderCol =
      sortBy === AdminUserSortBy.trips
        ? Prisma.sql`trip_count`
        : Prisma.sql`scan_credits`;
    const orderDir =
      sortDir === AdminSortDir.asc ? Prisma.sql`ASC` : Prisma.sql`DESC`;
    const searchClause = search
      ? Prisma.sql`WHERE (u.email ILIKE ${`%${search}%`} OR u.display_name ILIKE ${`%${search}%`})`
      : Prisma.empty;

    const rows = await this.prisma.$queryRaw<{ id: number }[]>`
      SELECT u.id,
             COALESCE(g.remaining_sum, 0) AS scan_credits,
             COALESCE(tm.trip_count, 0) AS trip_count
      FROM "user" u
      LEFT JOIN (
        SELECT user_id, SUM(remaining) AS remaining_sum
        FROM scan_credit_grant
        WHERE expires_at IS NULL OR expires_at > NOW()
        GROUP BY user_id
      ) g ON g.user_id = u.id
      LEFT JOIN (
        SELECT user_id, COUNT(*) AS trip_count
        FROM trip_member
        GROUP BY user_id
      ) tm ON tm.user_id = u.id
      ${searchClause}
      ORDER BY ${orderCol} ${orderDir}, u.id DESC
      LIMIT ${limit} OFFSET ${skip}
    `;
    return rows.map((r) => r.id);
  }

  async listAnalyticsEvents(
    query: AdminAnalyticsEventListQueryDto,
  ): Promise<AdminAnalyticsEventListResponseDto> {
    const page = query.page ?? 1;
    const limit = query.limit ?? 50;
    const skip = (page - 1) * limit;

    const where: Prisma.AnalyticsEventWhereInput = {};
    if (query.eventName) where.eventName = query.eventName;
    if (typeof query.userId === 'number') where.userId = query.userId;
    if (query.from || query.to) {
      where.occurredAt = {};
      if (query.from) where.occurredAt.gte = new Date(query.from);
      if (query.to) where.occurredAt.lte = new Date(query.to);
    }
    if (query.platform) where.session = { platform: query.platform };

    const [total, rows] = await Promise.all([
      this.prisma.analyticsEvent.count({ where }),
      this.prisma.analyticsEvent.findMany({
        where,
        orderBy: { occurredAt: 'desc' },
        skip,
        take: limit,
        select: {
          id: true,
          eventName: true,
          occurredAt: true,
          userId: true,
          sessionId: true,
          properties: true,
          user: { select: { email: true } },
          session: { select: { platform: true } },
        },
      }),
    ]);

    const items: AdminAnalyticsEventDto[] = rows.map((r) => ({
      id: r.id,
      eventName: r.eventName,
      occurredAt: r.occurredAt,
      userId: r.userId,
      userEmail: r.user?.email ?? null,
      sessionId: r.sessionId,
      platform: r.session?.platform ?? null,
      properties: (r.properties as Record<string, unknown> | null) ?? null,
    }));

    return { items, total, page, limit };
  }

  async getAnalyticsSummary(
    query: AdminAnalyticsSummaryQueryDto,
  ): Promise<AdminAnalyticsSummaryDto> {
    const now = new Date();
    const to = query.to ? new Date(query.to) : now;
    const defaultFrom = new Date(
      to.getTime() - DEFAULT_SUMMARY_WINDOW_DAYS * MS_PER_DAY,
    );
    let from = query.from ? new Date(query.from) : defaultFrom;
    const maxFrom = new Date(
      to.getTime() - MAX_SUMMARY_WINDOW_DAYS * MS_PER_DAY,
    );
    if (from < maxFrom) from = maxFrom;

    const where: Prisma.AnalyticsEventWhereInput = {
      occurredAt: { gte: from, lte: to },
    };

    const [
      byEventNameRows,
      byDayRows,
      totalEvents,
      distinctUsers,
      byPlatformRows,
    ] = await Promise.all([
      this.prisma.analyticsEvent.groupBy({
        by: ['eventName'],
        where,
        _count: { _all: true },
        orderBy: { _count: { eventName: 'desc' } },
      }),
      this.prisma.$queryRaw<
        { day: Date; event_name: AnalyticsEventName; count: bigint }[]
      >`
          SELECT date_trunc('day', occurred_at) AS day,
                 event_name,
                 COUNT(*)::bigint AS count
          FROM analytics_event
          WHERE occurred_at >= ${from} AND occurred_at <= ${to}
          GROUP BY 1, 2
          ORDER BY 1 ASC
        `,
      this.prisma.analyticsEvent.count({ where }),
      this.prisma.analyticsEvent.findMany({
        where: { ...where, userId: { not: null } },
        distinct: ['userId'],
        select: { userId: true },
      }),
      this.prisma.$queryRaw<{ platform: string; count: bigint }[]>`
          SELECT COALESCE(s.platform, 'unknown') AS platform,
                 COUNT(*)::bigint AS count
          FROM analytics_event e
          LEFT JOIN analytics_session s ON s.id = e.session_id
          WHERE e.occurred_at >= ${from} AND e.occurred_at <= ${to}
          GROUP BY COALESCE(s.platform, 'unknown')
          ORDER BY count DESC
        `,
    ]);

    const byEventName: AdminAnalyticsByEventDto[] = byEventNameRows.map(
      (row) => ({
        eventName: row.eventName,
        count: row._count._all,
      }),
    );

    const byDay: AdminAnalyticsByDayDto[] = byDayRows.map((row) => ({
      day: row.day.toISOString().slice(0, 10),
      eventName: row.event_name,
      count: Number(row.count),
    }));

    const byPlatform: AdminAnalyticsByPlatformDto[] = byPlatformRows.map(
      (row) => ({
        platform: row.platform,
        count: Number(row.count),
      }),
    );

    return {
      range: { from, to },
      totalEvents,
      totalUsers: distinctUsers.length,
      byEventName,
      byDay,
      byPlatform,
    };
  }

  async getUsersAggregates(
    query: AdminUsersAggregatesQueryDto,
  ): Promise<AdminUsersAggregatesDto> {
    const now = new Date();
    const to = query.to ? new Date(query.to) : now;
    const defaultFrom = new Date(
      to.getTime() - DEFAULT_SUMMARY_WINDOW_DAYS * MS_PER_DAY,
    );
    let from = query.from ? new Date(query.from) : defaultFrom;
    const maxFrom = new Date(
      to.getTime() - MAX_SUMMARY_WINDOW_DAYS * MS_PER_DAY,
    );
    if (from < maxFrom) from = maxFrom;

    const [
      totalUsers,
      signupsByDayRows,
      authProviderRows,
      subStatusRows,
      subProductRows,
      payOnceUsers,
      newSubsByDayRows,
      churnByDayRows,
      activeSubsCountRows,
      topActiveRows,
    ] = await Promise.all([
      this.prisma.user.count(),
      this.prisma.$queryRaw<{ day: Date; count: bigint }[]>`
        SELECT date_trunc('day', created_at) AS day, COUNT(*)::bigint AS count
        FROM "user"
        WHERE created_at >= ${from} AND created_at <= ${to}
        GROUP BY 1 ORDER BY 1 ASC
      `,
      this.prisma.authAccount.groupBy({
        by: ['provider'],
        _count: { _all: true },
      }),
      this.prisma.user.groupBy({
        by: ['subscriptionStatus'],
        _count: { _all: true },
      }),
      this.prisma.user.groupBy({
        by: ['subscriptionProductId'],
        _count: { _all: true },
      }),
      this.prisma.subscriptionTransaction.findMany({
        where: { productId: PAY_ONCE_SKU, revocationDate: null },
        distinct: ['userId'],
        select: { userId: true },
      }),
      this.prisma.$queryRaw<{ day: Date; count: bigint }[]>`
        SELECT date_trunc('day', purchase_date) AS day, COUNT(*)::bigint AS count
        FROM subscription_transaction
        WHERE purchase_date >= ${from} AND purchase_date <= ${to}
          AND revocation_date IS NULL
          AND transaction_id = original_transaction_id
          AND product_id IN (${Prisma.join(PRO_SUBSCRIPTION_SKUS)})
        GROUP BY 1 ORDER BY 1 ASC
      `,
      this.prisma.$queryRaw<{ day: Date; count: bigint }[]>`
        SELECT date_trunc('day', revocation_date) AS day, COUNT(*)::bigint AS count
        FROM subscription_transaction
        WHERE revocation_date >= ${from} AND revocation_date <= ${to}
          AND product_id IN (${Prisma.join(PRO_SUBSCRIPTION_SKUS)})
        GROUP BY 1 ORDER BY 1 ASC
      `,
      this.prisma.$queryRaw<{ count: bigint }[]>`
        SELECT COUNT(*)::bigint AS count FROM (
          SELECT id AS user_id FROM "user"
           WHERE subscription_status IN ('ACTIVE','GRACE_PERIOD','BILLING_RETRY')
          UNION
          SELECT DISTINCT user_id FROM subscription_transaction
           WHERE product_id = ${PAY_ONCE_SKU} AND revocation_date IS NULL
        ) u
      `,
      this.prisma.analyticsEvent.groupBy({
        by: ['userId'],
        where: {
          occurredAt: { gte: from, lte: to },
          userId: { not: null },
        },
        _count: { _all: true },
        orderBy: { _count: { userId: 'desc' } },
        take: 10,
      }),
    ]);

    const topUserIds = topActiveRows
      .map((row) => row.userId)
      .filter((id): id is number => id !== null);
    const topUsers = topUserIds.length
      ? await this.prisma.user.findMany({
          where: { id: { in: topUserIds } },
          select: { id: true, email: true, displayName: true },
        })
      : [];
    const topUsersById = new Map(topUsers.map((u) => [u.id, u]));

    const toCountByDay = (rows: { day: Date; count: bigint }[]) =>
      rows.map<AdminCountByDayDto>((row) => ({
        day: row.day.toISOString().slice(0, 10),
        count: Number(row.count),
      }));

    return {
      totalUsers,
      signupsByDay: toCountByDay(signupsByDayRows),
      byAuthProvider: authProviderRows.map((row) => ({
        provider: row.provider,
        count: row._count._all,
      })),
      bySubscriptionStatus: subStatusRows.map((row) => ({
        status: row.subscriptionStatus,
        count: row._count._all,
      })),
      bySubscriptionProduct: subProductRows.map((row) => ({
        productId: row.subscriptionProductId ?? 'none',
        count: row._count._all,
      })),
      activeSubscriptions: Number(activeSubsCountRows[0]?.count ?? 0),
      activePayOnce: payOnceUsers.length,
      newSubsByDay: toCountByDay(newSubsByDayRows),
      churnByDay: toCountByDay(churnByDayRows),
      topActiveUsers: topActiveRows
        .filter((row) => row.userId !== null)
        .map((row) => {
          const u = topUsersById.get(row.userId as number);
          return {
            userId: row.userId as number,
            email: u?.email ?? '',
            displayName: u?.displayName ?? '',
            eventCount: row._count._all,
          };
        }),
    };
  }

  async listTrips(
    query: AdminTripListQueryDto,
  ): Promise<AdminTripListResponseDto> {
    const page = query.page ?? 1;
    const limit = query.limit ?? 25;
    const skip = (page - 1) * limit;
    const sortBy = query.sortBy ?? AdminTripSortBy.createdAt;
    const sortDir = query.sortDir ?? AdminSortDir.desc;

    const where: Prisma.TripWhereInput = {};
    if (query.search)
      where.name = { contains: query.search, mode: 'insensitive' };
    if (query.status) where.status = query.status;

    const total = await this.prisma.trip.count({ where });

    // Computed columns (members, expenses) can't be sorted via Prisma orderBy,
    // so they take a raw-SQL path resolving the ordered page of ids first.
    const orderedIds =
      sortBy === AdminTripSortBy.members || sortBy === AdminTripSortBy.expenses
        ? await this.orderedTripIdsByComputed(
            query.search,
            query.status,
            sortBy,
            sortDir,
            limit,
            skip,
          )
        : null;

    const TRIP_SELECT = {
      id: true,
      name: true,
      status: true,
      currency: true,
      startDate: true,
      endDate: true,
      createdAt: true,
      createdBy: { select: { email: true, displayName: true } },
      _count: { select: { members: true, expenses: true } },
    } satisfies Prisma.TripSelect;

    const pageTrips = orderedIds
      ? await this.prisma.trip.findMany({
          where: { id: { in: orderedIds } },
          select: TRIP_SELECT,
        })
      : await this.prisma.trip.findMany({
          where,
          orderBy:
            sortBy === AdminTripSortBy.startDate
              ? { startDate: sortDir }
              : { createdAt: sortDir },
          skip,
          take: limit,
          select: TRIP_SELECT,
        });

    // Raw path returns ids in sorted order; findMany does not preserve it.
    const trips = orderedIds
      ? orderedIds
          .map((id) => pageTrips.find((t) => t.id === id))
          .filter((t): t is (typeof pageTrips)[number] => t !== undefined)
      : pageTrips;

    const items: AdminTripSummaryDto[] = trips.map((t) => ({
      id: t.id,
      name: t.name,
      status: t.status,
      creatorEmail: t.createdBy.email,
      creatorName: t.createdBy.displayName,
      memberCount: t._count.members,
      expenseCount: t._count.expenses,
      currency: t.currency,
      startDate: t.startDate,
      endDate: t.endDate,
      createdAt: t.createdAt,
    }));

    return { items, total, page, limit };
  }

  private async orderedTripIdsByComputed(
    search: string | undefined,
    status: TripStatus | undefined,
    sortBy: AdminTripSortBy,
    sortDir: AdminSortDir,
    limit: number,
    skip: number,
  ): Promise<number[]> {
    const orderCol =
      sortBy === AdminTripSortBy.members
        ? Prisma.sql`member_count`
        : Prisma.sql`expense_count`;
    const orderDir =
      sortDir === AdminSortDir.asc ? Prisma.sql`ASC` : Prisma.sql`DESC`;
    const conds: Prisma.Sql[] = [];
    if (search) conds.push(Prisma.sql`t.name ILIKE ${`%${search}%`}`);
    if (status) conds.push(Prisma.sql`t.status::text = ${status}`);
    const whereClause = conds.length
      ? Prisma.sql`WHERE ${Prisma.join(conds, ' AND ')}`
      : Prisma.empty;

    const rows = await this.prisma.$queryRaw<{ id: number }[]>`
      SELECT t.id,
             COALESCE(m.member_count, 0) AS member_count,
             COALESCE(e.expense_count, 0) AS expense_count
      FROM trip t
      LEFT JOIN (
        SELECT trip_id, COUNT(*) AS member_count
        FROM trip_member GROUP BY trip_id
      ) m ON m.trip_id = t.id
      LEFT JOIN (
        SELECT trip_id, COUNT(*) AS expense_count
        FROM expense GROUP BY trip_id
      ) e ON e.trip_id = t.id
      ${whereClause}
      ORDER BY ${orderCol} ${orderDir}, t.id DESC
      LIMIT ${limit} OFFSET ${skip}
    `;
    return rows.map((r) => r.id);
  }

  async getTripsAggregates(
    query: AdminTripsAggregatesQueryDto,
  ): Promise<AdminTripsAggregatesDto> {
    const now = new Date();
    const to = query.to ? new Date(query.to) : now;
    const defaultFrom = new Date(
      to.getTime() - DEFAULT_SUMMARY_WINDOW_DAYS * MS_PER_DAY,
    );
    let from = query.from ? new Date(query.from) : defaultFrom;
    const maxFrom = new Date(
      to.getTime() - MAX_SUMMARY_WINDOW_DAYS * MS_PER_DAY,
    );
    if (from < maxFrom) from = maxFrom;

    // Equal-length window immediately before [from,to] for the growth delta.
    const prevFrom = new Date(from.getTime() - (to.getTime() - from.getTime()));

    const [
      totalTrips,
      tripsInWindow,
      tripsInWindowPrev,
      tripsByDayRows,
      statusRows,
      currencyRows,
      memberStatsRows,
      sizeBucketRows,
      inviteRows,
      expenseStatsRows,
      expenseByCurrencyRows,
      topDestinationRows,
      featureRows,
      expenseByCategoryRows,
      durationRows,
      durationBucketRows,
      timingRows,
      tripsByMonthRows,
      tripsFromMarketplace,
      topCreatorRows,
      creatorStatsRows,
      topCountryRows,
      regionRows,
    ] = await Promise.all([
      this.prisma.trip.count(),
      this.prisma.trip.count({
        where: { createdAt: { gte: from, lte: to } },
      }),
      this.prisma.trip.count({
        where: { createdAt: { gte: prevFrom, lt: from } },
      }),
      this.prisma.$queryRaw<{ day: Date; count: bigint }[]>`
        SELECT date_trunc('day', created_at) AS day, COUNT(*)::bigint AS count
        FROM trip
        WHERE created_at >= ${from} AND created_at <= ${to}
        GROUP BY 1 ORDER BY 1 ASC
      `,
      this.prisma.trip.groupBy({ by: ['status'], _count: { _all: true } }),
      this.prisma.trip.groupBy({ by: ['currency'], _count: { _all: true } }),
      this.prisma.$queryRaw<{ total_members: bigint }[]>`
        SELECT COUNT(*)::bigint AS total_members FROM trip_member
      `,
      this.prisma.$queryRaw<{ bucket: string; count: bigint }[]>`
        SELECT bucket, COUNT(*)::bigint AS count FROM (
          SELECT t.id,
            CASE
              WHEN COUNT(tm.id) <= 1 THEN '1'
              WHEN COUNT(tm.id) <= 3 THEN '2-3'
              WHEN COUNT(tm.id) <= 6 THEN '4-6'
              ELSE '7+'
            END AS bucket
          FROM trip t
          LEFT JOIN trip_member tm ON tm.trip_id = t.id
          GROUP BY t.id
        ) s
        GROUP BY bucket
      `,
      this.prisma.$queryRaw<{ accepted: bigint; total: bigint }[]>`
        SELECT
          COUNT(*) FILTER (WHERE invite_status = 'ACCEPTED')::bigint AS accepted,
          COUNT(*)::bigint AS total
        FROM trip_member
      `,
      this.prisma.$queryRaw<
        { total_expenses: bigint; trips_with_expenses: bigint }[]
      >`
        SELECT COUNT(*)::bigint AS total_expenses,
               COUNT(DISTINCT trip_id)::bigint AS trips_with_expenses
        FROM expense
      `,
      this.prisma.$queryRaw<{ currency: Currency; total: Prisma.Decimal }[]>`
        SELECT t.currency AS currency, COALESCE(SUM(e.amount), 0) AS total
        FROM expense e
        JOIN trip t ON t.id = e.trip_id
        GROUP BY t.currency
      `,
      this.prisma.$queryRaw<{ name: string; count: bigint }[]>`
        SELECT COALESCE(c.name, co.name) AS name, COUNT(*)::bigint AS count
        FROM trip t
        LEFT JOIN city c ON c.id = t.city_id
        LEFT JOIN country co ON co.id = t.country_id
        WHERE c.name IS NOT NULL OR co.name IS NOT NULL
        GROUP BY COALESCE(c.name, co.name)
        ORDER BY count DESC
        LIMIT 10
      `,
      // Feature adoption: one query, trips-with-≥1 + total rows per feature.
      this.prisma.$queryRaw<
        {
          photo_trips: bigint;
          photo_total: bigint;
          chat_trips: bigint;
          chat_total: bigint;
          plan_trips: bigint;
          plan_total: bigint;
          budget_trips: bigint;
          budget_total: bigint;
          expense_trips: bigint;
          expense_total: bigint;
        }[]
      >`
        SELECT
          (SELECT COUNT(DISTINCT trip_id) FROM trip_photo)::bigint AS photo_trips,
          (SELECT COUNT(*) FROM trip_photo)::bigint AS photo_total,
          (SELECT COUNT(DISTINCT trip_id) FROM chat_message)::bigint AS chat_trips,
          (SELECT COUNT(*) FROM chat_message)::bigint AS chat_total,
          (SELECT COUNT(DISTINCT trip_id) FROM trip_plan_item)::bigint AS plan_trips,
          (SELECT COUNT(*) FROM trip_plan_item)::bigint AS plan_total,
          (SELECT COUNT(DISTINCT trip_id) FROM budget)::bigint AS budget_trips,
          (SELECT COUNT(*) FROM budget)::bigint AS budget_total,
          (SELECT COUNT(DISTINCT trip_id) FROM expense)::bigint AS expense_trips,
          (SELECT COUNT(*) FROM expense)::bigint AS expense_total
      `,
      this.prisma.expense.groupBy({ by: ['category'], _count: { _all: true } }),
      this.prisma.$queryRaw<{ avg_days: number }[]>`
        SELECT COALESCE(AVG(end_date - start_date), 0)::float8 AS avg_days
        FROM trip
        WHERE start_date IS NOT NULL AND end_date IS NOT NULL
      `,
      this.prisma.$queryRaw<{ bucket: string; count: bigint }[]>`
        SELECT bucket, COUNT(*)::bigint AS count FROM (
          SELECT CASE
            WHEN (end_date - start_date) <= 2 THEN '1-2'
            WHEN (end_date - start_date) <= 5 THEN '3-5'
            WHEN (end_date - start_date) <= 9 THEN '6-9'
            ELSE '10+'
          END AS bucket
          FROM trip
          WHERE start_date IS NOT NULL AND end_date IS NOT NULL
        ) s
        GROUP BY bucket
      `,
      this.prisma.$queryRaw<{ upcoming: bigint; past: bigint }[]>`
        SELECT
          COUNT(*) FILTER (WHERE start_date >= CURRENT_DATE)::bigint AS upcoming,
          COUNT(*) FILTER (WHERE start_date < CURRENT_DATE)::bigint AS past
        FROM trip
        WHERE start_date IS NOT NULL
      `,
      this.prisma.$queryRaw<{ month: string; count: bigint }[]>`
        SELECT to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM') AS month,
               COUNT(*)::bigint AS count
        FROM trip
        WHERE created_at >= ${from} AND created_at <= ${to}
        GROUP BY 1 ORDER BY 1 ASC
      `,
      this.prisma.trip.count({
        where: { marketplaceListingId: { not: null } },
      }),
      this.prisma.$queryRaw<{ user_id: number; trip_count: bigint }[]>`
        SELECT created_by_id AS user_id, COUNT(*)::bigint AS trip_count
        FROM trip
        GROUP BY created_by_id
        ORDER BY trip_count DESC
        LIMIT 10
      `,
      this.prisma.$queryRaw<
        { total_creators: bigint; repeat_creators: bigint }[]
      >`
        SELECT COUNT(*)::bigint AS total_creators,
               COUNT(*) FILTER (WHERE cnt > 1)::bigint AS repeat_creators
        FROM (
          SELECT created_by_id, COUNT(*) AS cnt FROM trip GROUP BY created_by_id
        ) c
      `,
      this.prisma.$queryRaw<{ name: string; count: bigint }[]>`
        SELECT co.name AS name, COUNT(*)::bigint AS count
        FROM trip t
        JOIN country co ON co.id = t.country_id
        GROUP BY co.name
        ORDER BY count DESC
        LIMIT 10
      `,
      this.prisma.$queryRaw<{ name: string; count: bigint }[]>`
        SELECT COALESCE(co.region, 'Unknown') AS name, COUNT(*)::bigint AS count
        FROM trip t
        JOIN country co ON co.id = t.country_id
        GROUP BY COALESCE(co.region, 'Unknown')
        ORDER BY count DESC
        LIMIT 10
      `,
    ]);

    const totalMembers = Number(memberStatsRows[0]?.total_members ?? 0);
    const accepted = Number(inviteRows[0]?.accepted ?? 0);
    const totalInvites = Number(inviteRows[0]?.total ?? 0);
    const totalExpenses = Number(expenseStatsRows[0]?.total_expenses ?? 0);
    const tripsWithExpenses = Number(
      expenseStatsRows[0]?.trips_with_expenses ?? 0,
    );
    const totalCreators = Number(creatorStatsRows[0]?.total_creators ?? 0);
    const repeatCreators = Number(creatorStatsRows[0]?.repeat_creators ?? 0);

    // Resolve creator identities for the top-creator list (mirrors topActiveUsers).
    const creatorIds = topCreatorRows.map((r) => r.user_id);
    const creators = creatorIds.length
      ? await this.prisma.user.findMany({
          where: { id: { in: creatorIds } },
          select: { id: true, email: true, displayName: true },
        })
      : [];
    const creatorsById = new Map(creators.map((u) => [u.id, u]));

    const round = (n: number, dp: number) => {
      const f = 10 ** dp;
      return Math.round(n * f) / f;
    };

    const fr = featureRows[0];
    const featureAdoption = [
      { feature: 'photos', trips: fr?.photo_trips, total: fr?.photo_total },
      { feature: 'chat', trips: fr?.chat_trips, total: fr?.chat_total },
      { feature: 'planItems', trips: fr?.plan_trips, total: fr?.plan_total },
      { feature: 'budgets', trips: fr?.budget_trips, total: fr?.budget_total },
      {
        feature: 'expenses',
        trips: fr?.expense_trips,
        total: fr?.expense_total,
      },
    ].map((f) => ({
      feature: f.feature,
      tripCount: Number(f.trips ?? 0),
      avgPerTrip:
        totalTrips > 0 ? round(Number(f.total ?? 0) / totalTrips, 2) : 0,
    }));

    return {
      totalTrips,
      tripsInWindow,
      tripsByDay: tripsByDayRows.map((r) => ({
        day: r.day.toISOString().slice(0, 10),
        count: Number(r.count),
      })),
      byStatus: statusRows.map((r) => ({
        status: r.status,
        count: r._count._all,
      })),
      avgMembersPerTrip:
        totalTrips > 0 ? round(totalMembers / totalTrips, 2) : 0,
      tripSizeBuckets: ['1', '2-3', '4-6', '7+'].map((bucket) => ({
        bucket,
        count: Number(
          sizeBucketRows.find((r) => r.bucket === bucket)?.count ?? 0,
        ),
      })),
      inviteAcceptanceRate:
        totalInvites > 0 ? round(accepted / totalInvites, 3) : 0,
      avgExpensesPerTrip:
        totalTrips > 0 ? round(totalExpenses / totalTrips, 2) : 0,
      tripsWithExpenses,
      expenseTotalsByCurrency: expenseByCurrencyRows.map((r) => ({
        currency: r.currency,
        total: Number(String(r.total)),
      })),
      byCurrency: currencyRows.map((r) => ({
        currency: r.currency,
        count: r._count._all,
      })),
      topDestinations: topDestinationRows.map((r) => ({
        name: r.name,
        count: Number(r.count),
      })),
      tripsInWindowPrev,
      featureAdoption,
      expenseByCategory: expenseByCategoryRows.map((r) => ({
        category: r.category,
        count: r._count._all,
      })),
      avgDurationDays: round(Number(durationRows[0]?.avg_days ?? 0), 1),
      durationBuckets: ['1-2', '3-5', '6-9', '10+'].map((bucket) => ({
        bucket,
        count: Number(
          durationBucketRows.find((r) => r.bucket === bucket)?.count ?? 0,
        ),
      })),
      upcomingTrips: Number(timingRows[0]?.upcoming ?? 0),
      pastTrips: Number(timingRows[0]?.past ?? 0),
      tripsByMonth: tripsByMonthRows.map((r) => ({
        month: r.month,
        count: Number(r.count),
      })),
      tripsFromMarketplace,
      topCreators: topCreatorRows.map((r) => {
        const u = creatorsById.get(r.user_id);
        return {
          userId: r.user_id,
          email: u?.email ?? '',
          displayName: u?.displayName ?? '',
          tripCount: Number(r.trip_count),
        };
      }),
      repeatCreatorRate:
        totalCreators > 0 ? round(repeatCreators / totalCreators, 3) : 0,
      avgTripsPerCreator:
        totalCreators > 0 ? round(totalTrips / totalCreators, 2) : 0,
      topCountries: topCountryRows.map((r) => ({
        name: r.name,
        count: Number(r.count),
      })),
      byRegion: regionRows.map((r) => ({
        name: r.name,
        count: Number(r.count),
      })),
    };
  }

  async getUserDetail(id: number): Promise<AdminUserDetailDto> {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: {
        id: true,
        email: true,
        displayName: true,
        avatarUrl: true,
        createdAt: true,
        subscriptionStatus: true,
        subscriptionProductId: true,
        subscriptionExpiresAt: true,
        authAccounts: { select: { provider: true } },
        _count: { select: { tripMembers: true } },
      },
    });
    if (!user) throw new NotFoundException('User not found');

    const [
      grantSum,
      trips,
      subscriptionHistory,
      scanCreditGrants,
      scanCreditConsumptions,
      recentEvents,
    ] = await Promise.all([
      this.prisma.scanCreditGrant.aggregate({
        where: {
          userId: id,
          OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
        },
        _sum: { remaining: true },
      }),
      this.prisma.tripMember.findMany({
        where: { userId: id },
        orderBy: { joinedAt: 'desc' },
        take: 50,
        select: {
          inviteStatus: true,
          joinedAt: true,
          trip: { select: { id: true, name: true, status: true } },
        },
      }),
      this.prisma.subscriptionTransaction.findMany({
        where: { userId: id },
        orderBy: { purchaseDate: 'desc' },
        take: 50,
        select: {
          id: true,
          productId: true,
          transactionId: true,
          originalTransactionId: true,
          purchaseDate: true,
          expiresDate: true,
          revocationDate: true,
          notificationType: true,
          environment: true,
        },
      }),
      this.prisma.scanCreditGrant.findMany({
        where: { userId: id },
        orderBy: { grantedAt: 'desc' },
        take: 50,
        select: {
          id: true,
          source: true,
          productId: true,
          amount: true,
          remaining: true,
          grantedAt: true,
          expiresAt: true,
          revokedAt: true,
          externalRef: true,
          periodKey: true,
        },
      }),
      this.prisma.scanCreditConsumption.findMany({
        where: { userId: id },
        orderBy: { consumedAt: 'desc' },
        take: 50,
        select: {
          id: true,
          grantId: true,
          sessionId: true,
          amount: true,
          consumedAt: true,
          refundedAt: true,
        },
      }),
      this.prisma.analyticsEvent.findMany({
        where: { userId: id },
        orderBy: { occurredAt: 'desc' },
        take: 50,
        select: {
          id: true,
          eventName: true,
          occurredAt: true,
          userId: true,
          sessionId: true,
          properties: true,
          session: { select: { platform: true } },
        },
      }),
    ]);

    return {
      user: {
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
        createdAt: user.createdAt,
        authProviders: Array.from(
          new Set(user.authAccounts.map((a) => a.provider)),
        ),
        subscriptionStatus: user.subscriptionStatus,
        subscriptionProductId: user.subscriptionProductId,
        subscriptionExpiresAt: user.subscriptionExpiresAt,
        scanCreditsRemaining: grantSum._sum.remaining ?? 0,
        tripCount: user._count.tripMembers,
      },
      trips: trips.map((t) => ({
        id: t.trip.id,
        name: t.trip.name,
        status: t.trip.status,
        inviteStatus: t.inviteStatus,
        joinedAt: t.joinedAt,
      })),
      subscriptionHistory: subscriptionHistory.map((s) => ({
        ...s,
        platform: /^\d+$/.test(s.transactionId) ? 'apple' : 'android',
      })),
      scanCreditGrants,
      scanCreditConsumptions,
      recentEvents: recentEvents.map((r) => ({
        id: r.id,
        eventName: r.eventName,
        occurredAt: r.occurredAt,
        userId: r.userId,
        userEmail: user.email,
        sessionId: r.sessionId,
        platform: r.session?.platform ?? null,
        properties: (r.properties as Record<string, unknown> | null) ?? null,
      })),
    };
  }

  async getTripDetail(id: number): Promise<AdminTripDetailDto> {
    const userRef = {
      select: {
        id: true,
        email: true,
        displayName: true,
        avatarUrl: true,
      },
    } as const;

    const trip = await this.prisma.trip.findUnique({
      where: { id },
      select: {
        id: true,
        name: true,
        status: true,
        coverImageUrl: true,
        inviteCode: true,
        currency: true,
        localCurrencies: true,
        startDate: true,
        endDate: true,
        createdAt: true,
        updatedAt: true,
        createdBy: userRef,
        city: { select: { name: true } },
        state: { select: { name: true } },
        country: { select: { name: true } },
        marketplaceListing: {
          select: { id: true, publicId: true, name: true, status: true },
        },
        _count: {
          select: {
            members: true,
            expenses: true,
            budgets: true,
            planItems: true,
            photos: true,
            notes: true,
            chatMessages: true,
            activities: true,
          },
        },
      },
    });
    if (!trip) throw new NotFoundException('Trip not found');

    const [members, expenses, budgets, planItems, photos, notes, activities] =
      await Promise.all([
        this.prisma.tripMember.findMany({
          where: { tripId: id },
          orderBy: { createdAt: 'asc' },
          select: { inviteStatus: true, joinedAt: true, user: userRef },
        }),
        this.prisma.expense.findMany({
          where: { tripId: id },
          orderBy: { expenseDate: 'desc' },
          take: 50,
          select: {
            id: true,
            name: true,
            note: true,
            amount: true,
            originalCurrency: true,
            category: true,
            expenseDate: true,
            paidBy: userRef,
            _count: { select: { shares: true } },
          },
        }),
        this.prisma.budget.findMany({
          where: { tripId: id },
          orderBy: { createdAt: 'asc' },
          select: {
            id: true,
            name: true,
            amount: true,
            perPersonAmount: true,
            scope: true,
            originalAmount: true,
            originalCurrency: true,
          },
        }),
        this.prisma.tripPlanItem.findMany({
          where: { tripId: id },
          orderBy: [
            { planDate: 'asc' },
            { dayNumber: 'asc' },
            { sortOrder: 'asc' },
          ],
          take: 50,
          select: {
            id: true,
            title: true,
            description: true,
            planDate: true,
            dayNumber: true,
            startTime: true,
            location: true,
            address: true,
            category: true,
          },
        }),
        this.prisma.tripPhoto.findMany({
          where: { tripId: id },
          orderBy: { createdAt: 'desc' },
          take: 50,
          select: {
            id: true,
            photoUrl: true,
            caption: true,
            createdAt: true,
            uploadedBy: userRef,
          },
        }),
        this.prisma.tripNote.findMany({
          where: { tripId: id },
          orderBy: { updatedAt: 'desc' },
          take: 50,
          select: {
            id: true,
            title: true,
            body: true,
            isDone: true,
            updatedAt: true,
            createdBy: userRef,
          },
        }),
        this.prisma.tripActivity.findMany({
          where: { tripId: id },
          orderBy: { createdAt: 'desc' },
          take: 50,
          select: { id: true, action: true, createdAt: true, user: userRef },
        }),
      ]);

    return {
      trip: {
        id: trip.id,
        name: trip.name,
        status: trip.status,
        coverImageUrl: trip.coverImageUrl,
        inviteCode: trip.inviteCode,
        currency: trip.currency,
        localCurrencies: trip.localCurrencies,
        startDate: trip.startDate,
        endDate: trip.endDate,
        createdAt: trip.createdAt,
        updatedAt: trip.updatedAt,
        creator: trip.createdBy,
        cityName: trip.city?.name ?? null,
        stateName: trip.state?.name ?? null,
        countryName: trip.country?.name ?? null,
        marketplaceListing: trip.marketplaceListing,
        counts: trip._count,
      },
      members: members.map((m) => ({
        userId: m.user.id,
        email: m.user.email,
        displayName: m.user.displayName,
        avatarUrl: m.user.avatarUrl,
        inviteStatus: m.inviteStatus,
        joinedAt: m.joinedAt,
      })),
      expenses: expenses.map((e) => ({
        id: e.id,
        name: e.name,
        note: e.note,
        amount: Number(e.amount),
        originalCurrency: e.originalCurrency,
        category: e.category,
        paidBy: e.paidBy,
        expenseDate: e.expenseDate,
        shareCount: e._count.shares,
      })),
      budgets: budgets.map((b) => ({
        id: b.id,
        name: b.name,
        amount: Number(b.amount),
        perPersonAmount:
          b.perPersonAmount === null ? null : Number(b.perPersonAmount),
        scope: b.scope,
        originalAmount:
          b.originalAmount === null ? null : Number(b.originalAmount),
        originalCurrency: b.originalCurrency,
      })),
      planItems,
      photos,
      notes,
      activities,
    };
  }
}
