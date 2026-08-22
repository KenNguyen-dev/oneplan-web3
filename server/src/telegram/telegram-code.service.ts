import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  TelegramCodeListQueryDto,
  TelegramCodeListResponseDto,
  TelegramCodeStatus,
  TelegramOfferCodeItemDto,
} from './dto/telegram-code-list.dto';
import { TelegramStatsDto } from './dto/telegram-stats.dto';
import { UploadTelegramCodesResultDto } from './dto/upload-codes.dto';

// Result of a claim attempt. `reused` distinguishes a fresh assignment from an
// idempotent re-tap (same Telegram user asking again gets the same code).
export type ClaimResult =
  | { code: string; reused: boolean }
  | { exhausted: true };

@Injectable()
export class TelegramCodeService {
  constructor(private readonly prisma: PrismaService) {}

  // Bulk-insert codes, skipping any already in the pool (unique on `code`).
  async uploadCodes(
    codes: string[],
    batchLabel?: string | null,
  ): Promise<UploadTelegramCodesResultDto> {
    // De-dupe + trim within the request itself; skipDuplicates handles
    // collisions against rows already in the table.
    const cleaned = Array.from(
      new Set(codes.map((c) => c.trim()).filter((c) => c.length > 0)),
    );
    if (cleaned.length === 0) return { inserted: 0, skipped: codes.length };

    const res = await this.prisma.telegramOfferCode.createMany({
      data: cleaned.map((code) => ({ code, batchLabel: batchLabel ?? null })),
      skipDuplicates: true,
    });
    return { inserted: res.count, skipped: codes.length - res.count };
  }

  // Assigns one offer code to a Telegram user. Idempotent per user via a
  // per-user advisory lock (mirrors scan-credit.service.ts): concurrent /start
  // from the same user serialize, so the "already assigned?" check is race-free.
  // The free-row pick uses FOR UPDATE SKIP LOCKED so two DIFFERENT users never
  // grab the same physical row. The partial unique index on
  // assigned_telegram_user_id is the belt-and-suspenders backstop.
  async claimCode(
    telegramUserId: bigint,
    username?: string | null,
  ): Promise<ClaimResult> {
    return this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(${telegramUserId})`;

      const existing = await tx.telegramOfferCode.findFirst({
        where: { assignedTelegramUserId: telegramUserId },
        select: { code: true },
      });
      if (existing) return { code: existing.code, reused: true };

      const rows = await tx.$queryRaw<{ code: string }[]>(Prisma.sql`
        UPDATE "telegram_offer_code"
        SET "assigned_telegram_user_id" = ${telegramUserId},
            "assigned_telegram_username" = ${username ?? null},
            "assigned_at" = NOW()
        WHERE "id" = (
          SELECT "id" FROM "telegram_offer_code"
          WHERE "assigned_telegram_user_id" IS NULL
          ORDER BY "id"
          LIMIT 1
          FOR UPDATE SKIP LOCKED
        )
        RETURNING "code"
      `);

      if (rows.length === 0) return { exhausted: true };
      return { code: rows[0].code, reused: false };
    });
  }

  // ── Admin reads ───────────────────────────────────────────────────────────

  async listCodes(
    query: TelegramCodeListQueryDto,
  ): Promise<TelegramCodeListResponseDto> {
    const page = query.page ?? 1;
    const limit = query.limit ?? 25;

    const where: Prisma.TelegramOfferCodeWhereInput = {};
    if (query.status === TelegramCodeStatus.available) {
      where.assignedTelegramUserId = null;
    } else if (query.status === TelegramCodeStatus.assigned) {
      where.assignedTelegramUserId = { not: null };
    }
    if (query.batchLabel) where.batchLabel = query.batchLabel;
    const search = query.search?.trim();
    if (search) where.code = { contains: search, mode: 'insensitive' };

    const [rows, total] = await Promise.all([
      this.prisma.telegramOfferCode.findMany({
        where,
        orderBy: { id: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.telegramOfferCode.count({ where }),
    ]);

    return {
      items: rows.map((r) => this.toItemDto(r)),
      total,
      page,
      limit,
    };
  }

  // Permanently removes a code from the pool. Allowed for any code, including
  // already-assigned ones (admin chose flexible cleanup over preserving the
  // issued-code record). Idempotent: deleting a missing id is a no-op.
  async deleteCode(id: number): Promise<{ deleted: boolean }> {
    const res = await this.prisma.telegramOfferCode.deleteMany({
      where: { id },
    });
    return { deleted: res.count > 0 };
  }

  async stats(opts: {
    campaignEnabled: boolean;
    botEnabled: boolean;
  }): Promise<TelegramStatsDto> {
    const [total, issued, byBatchTotal, byBatchIssued, issuedByDayRows] =
      await Promise.all([
        this.prisma.telegramOfferCode.count(),
        this.prisma.telegramOfferCode.count({
          where: { assignedTelegramUserId: { not: null } },
        }),
        this.prisma.telegramOfferCode.groupBy({
          by: ['batchLabel'],
          _count: { _all: true },
        }),
        this.prisma.telegramOfferCode.groupBy({
          by: ['batchLabel'],
          where: { assignedTelegramUserId: { not: null } },
          _count: { _all: true },
        }),
        this.prisma.$queryRaw<{ day: string; count: number }[]>(Prisma.sql`
          SELECT to_char(date_trunc('day', "assigned_at"), 'YYYY-MM-DD') AS day,
                 COUNT(*)::int AS count
          FROM "telegram_offer_code"
          WHERE "assigned_at" IS NOT NULL
          GROUP BY 1
          ORDER BY 1
        `),
      ]);

    const issuedByBatch = new Map(
      byBatchIssued.map((g) => [g.batchLabel, g._count._all]),
    );
    const byBatch = byBatchTotal.map((g) => {
      const batchIssued = issuedByBatch.get(g.batchLabel) ?? 0;
      return {
        batchLabel: g.batchLabel,
        total: g._count._all,
        issued: batchIssued,
        available: g._count._all - batchIssued,
      };
    });

    return {
      campaignEnabled: opts.campaignEnabled,
      botEnabled: opts.botEnabled,
      totalCodes: total,
      available: total - issued,
      issued,
      byBatch,
      issuedByDay: issuedByDayRows.map((r) => ({
        day: r.day,
        count: Number(r.count),
      })),
    };
  }

  private toItemDto(row: {
    id: number;
    code: string;
    batchLabel: string | null;
    assignedTelegramUserId: bigint | null;
    assignedTelegramUsername: string | null;
    assignedAt: Date | null;
    createdAt: Date;
  }): TelegramOfferCodeItemDto {
    return {
      id: row.id,
      code: row.code,
      batchLabel: row.batchLabel,
      status:
        row.assignedTelegramUserId === null
          ? TelegramCodeStatus.available
          : TelegramCodeStatus.assigned,
      // BigInt can exceed 2^53 and Fastify's JSON serializer throws on raw
      // BigInt, so serialize as a string.
      assignedTelegramUserId:
        row.assignedTelegramUserId === null
          ? null
          : row.assignedTelegramUserId.toString(),
      assignedTelegramUsername: row.assignedTelegramUsername,
      assignedAt: row.assignedAt,
      createdAt: row.createdAt,
    };
  }
}
