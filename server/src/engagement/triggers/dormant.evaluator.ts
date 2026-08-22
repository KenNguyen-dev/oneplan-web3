import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { EngagementTrigger } from '@prisma/client';
import { ENGAGEMENT_PUSH_TYPE } from '../engagement.constants';
import {
  TriggerCandidate,
  TriggerEvaluator,
  UserEngagementContext,
} from '../engagement.types';
import { isoWeekKey } from '../engagement.util';

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Re-engages users who haven't opened the app in N days. Lowest-priority
 * (catch-all) trigger. Keyed once per ISO week so a still-dormant user isn't
 * nagged every single day.
 */
@Injectable()
export class DormantEvaluator implements TriggerEvaluator {
  readonly trigger = EngagementTrigger.DORMANT;

  constructor(private readonly config: ConfigService) {}

  isEnabled(): boolean {
    return this.config.get<string>('ENGAGEMENT_TRIGGER_DORMANT') === 'true';
  }

  evaluate(
    ctx: UserEngagementContext,
    now: Date,
  ): Promise<TriggerCandidate | null> {
    // No session signal at all → no dormancy evidence, skip (avoids nagging
    // brand-new users who simply haven't generated an analytics session yet).
    if (!ctx.lastSessionAt) return Promise.resolve(null);

    const days = this.config.get<number>('ENGAGEMENT_DORMANT_DAYS') ?? 14;
    const ageMs = now.getTime() - ctx.lastSessionAt.getTime();
    if (ageMs < days * DAY_MS) return Promise.resolve(null);

    const cityName = ctx.trips[0]?.cityName ?? undefined;
    return Promise.resolve({
      trigger: this.trigger,
      dedupeKey: `DORMANT:user:${ctx.userId}:${isoWeekKey(now)}`,
      hints: { cityName, coarseHint: 'generic' },
      deepLink: { type: ENGAGEMENT_PUSH_TYPE.DORMANT },
    });
  }
}
