import { Injectable, Logger } from '@nestjs/common';
import { EngagementLocale, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { GeneratedCopy, TriggerCandidate } from './engagement.types';

export const ENGAGEMENT_CAP_WINDOW_MS = 24 * 60 * 60 * 1000;

/**
 * Owns the EngagementNotification log: the per-trigger idempotency guard and
 * the auditable record of what was sent. The cron writes the log BEFORE the
 * push so a crash mid-batch can never resend (worst case: a logged-but-
 * undelivered push). `claim` returns false on a unique (dedupeKey) collision,
 * which also closes overlapping-cron-tick races.
 */
@Injectable()
export class EngagementFrequencyService {
  private readonly logger = new Logger(EngagementFrequencyService.name);

  constructor(private readonly prisma: PrismaService) {}

  /** True if the user already got an engagement push within the 24h window. */
  async isCapped(userId: number, now: Date): Promise<boolean> {
    const cutoff = new Date(now.getTime() - ENGAGEMENT_CAP_WINDOW_MS);
    const recent = await this.prisma.engagementNotification.findFirst({
      where: { userId, sentAt: { gte: cutoff } },
      select: { id: true },
    });
    return recent !== null;
  }

  /**
   * Insert the log row (claiming the dedupeKey). Returns the new row's id, or
   * null if the dedupeKey already exists (P2002) — meaning another tick already
   * handled this exact candidate, so the caller should skip the send.
   */
  async claim(
    userId: number,
    locale: EngagementLocale,
    candidate: TriggerCandidate,
    copy: GeneratedCopy,
  ): Promise<number | null> {
    try {
      const row = await this.prisma.engagementNotification.create({
        data: {
          userId,
          trigger: candidate.trigger,
          tripId: candidate.tripId ?? null,
          listingId: candidate.listingId ?? null,
          dedupeKey: candidate.dedupeKey,
          title: copy.title,
          body: copy.body,
          locale,
          usedLlm: copy.usedLlm,
        },
        select: { id: true },
      });
      return row.id;
    } catch (err) {
      if (
        err instanceof Prisma.PrismaClientKnownRequestError &&
        err.code === 'P2002'
      ) {
        return null;
      }
      throw err;
    }
  }
}
