import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron } from '@nestjs/schedule';
import { AnalyticsEventName } from '@prisma/client';
import { AnalyticsService } from '../analytics/analytics.service';
import { NotificationsService } from '../notifications/notifications.service';
import { localHourInTimezone, parseTimezone } from '../common/timezone.util';
import { EngagementCopyService } from './engagement-copy.service';
import { EngagementFrequencyService } from './engagement-frequency.service';
import { EngagementTargetingService } from './engagement-targeting.service';
import { TRIGGER_PRIORITY } from './engagement.constants';
import {
  ENGAGEMENT_EVALUATORS,
  TriggerEvaluator,
  UserEngagementContext,
} from './engagement.types';

// Bound the work per tick so a growing user base can't make one tick run for
// minutes; leftover users are picked up on the next tick. 20 * 500 = 10k users.
const MAX_PAGES_PER_TICK = 20;

/**
 * The engagement-push engine. Every 15 minutes it scans candidate users, and
 * for each (within their local daytime window, capped at 1/24h) evaluates the
 * enabled triggers in fixed priority order, picks ONE, generates localized
 * copy, logs it (claiming the dedupeKey), and sends a single APN.
 *
 * `waitForCompletion: true` prevents a slow tick from overlapping the next;
 * correctness against overlap is already guaranteed by the dedupeKey claim.
 */
@Injectable()
export class EngagementCronService {
  private readonly logger = new Logger(EngagementCronService.name);
  private readonly orderedEvaluators: TriggerEvaluator[];

  constructor(
    private readonly config: ConfigService,
    private readonly targeting: EngagementTargetingService,
    private readonly copy: EngagementCopyService,
    private readonly frequency: EngagementFrequencyService,
    private readonly notifications: NotificationsService,
    private readonly analytics: AnalyticsService,
    @Inject(ENGAGEMENT_EVALUATORS) evaluators: TriggerEvaluator[],
  ) {
    const byTrigger = new Map(evaluators.map((e) => [e.trigger, e]));
    this.orderedEvaluators = TRIGGER_PRIORITY.map((t) =>
      byTrigger.get(t),
    ).filter((e): e is TriggerEvaluator => e != null);
  }

  @Cron('*/15 * * * *', { name: 'engagement', waitForCompletion: true })
  async run(): Promise<void> {
    if (this.config.get<string>('ENGAGEMENT_ENABLED') !== 'true') return;

    const activeEvaluators = this.orderedEvaluators.filter((e) =>
      e.isEnabled(),
    );
    if (activeEvaluators.length === 0) return;

    const startHour =
      this.config.get<number>('ENGAGEMENT_SEND_START_HOUR') ?? 10;
    const endHour = this.config.get<number>('ENGAGEMENT_SEND_END_HOUR') ?? 20;
    const defaultTz =
      this.config.get<string>('WEATHER_DEFAULT_TIMEZONE') ?? 'Asia/Ho_Chi_Minh';

    const cronStart = new Date();
    let afterId = 0;
    let sent = 0;

    for (let page = 0; page < MAX_PAGES_PER_TICK; page++) {
      const candidates = await this.targeting.loadCandidatePage(
        cronStart,
        afterId,
      );
      if (candidates.length === 0) break;

      for (const ctx of candidates) {
        const now = new Date();
        const tz = this.resolveTimezone(ctx, defaultTz);
        const hour = localHourInTimezone(tz, now);
        if (hour < startHour || hour >= endHour) continue;

        const candidate = await this.pickCandidate(activeEvaluators, ctx, now);
        if (!candidate) continue;

        const copy = await this.copy.generate(candidate, ctx.locale);

        // Log BEFORE sending: a crash after this leaves a logged-but-undelivered
        // push (acceptable) rather than risking a resend. P2002 → skip.
        const claimed = await this.frequency.claim(
          ctx.userId,
          ctx.locale,
          candidate,
          copy,
        );
        if (claimed === null) continue;

        try {
          await this.notifications.sendEngagementPush(
            ctx.userId,
            copy.title,
            copy.body,
            candidate.deepLink,
          );
        } catch (err) {
          this.logger.error(
            `Failed to deliver engagement push to user ${ctx.userId}: ${
              err instanceof Error ? err.message : String(err)
            }`,
          );
        }

        void this.analytics.track(AnalyticsEventName.ENGAGEMENT_PUSH_SENT, {
          userId: ctx.userId,
          properties: {
            trigger: candidate.trigger,
            usedLlm: copy.usedLlm,
            ...(candidate.tripId != null ? { tripId: candidate.tripId } : {}),
            ...(candidate.listingId != null
              ? { listingId: candidate.listingId }
              : {}),
          },
        });
        sent++;
      }

      afterId = candidates[candidates.length - 1].userId;
    }

    if (sent > 0) {
      this.logger.log(`Sent ${sent} engagement push(es)`);
    }
  }

  private async pickCandidate(
    evaluators: TriggerEvaluator[],
    ctx: UserEngagementContext,
    now: Date,
  ) {
    for (const ev of evaluators) {
      const candidate = await ev.evaluate(ctx, now);
      if (candidate) return candidate;
    }
    return null;
  }

  private resolveTimezone(
    ctx: UserEngagementContext,
    defaultTz: string,
  ): string {
    for (const trip of ctx.trips) {
      const tz = parseTimezone(trip.countryTimezones);
      if (tz) return tz;
    }
    return defaultTz;
  }
}
