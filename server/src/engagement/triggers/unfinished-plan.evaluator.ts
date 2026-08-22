import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { EngagementTrigger, TripStatus } from '@prisma/client';
import { ENGAGEMENT_PUSH_TYPE } from '../engagement.constants';
import {
  TriggerCandidate,
  TriggerEvaluator,
  UserEngagementContext,
} from '../engagement.types';

const HOUR_MS = 60 * 60 * 1000;

/**
 * Nudges a user whose freshly-created trip still has an (almost) empty plan.
 * Keyed per trip so a given trip is nagged at most once.
 */
@Injectable()
export class UnfinishedPlanEvaluator implements TriggerEvaluator {
  readonly trigger = EngagementTrigger.UNFINISHED_PLAN;

  constructor(private readonly config: ConfigService) {}

  isEnabled(): boolean {
    return this.config.get<string>('ENGAGEMENT_TRIGGER_UNFINISHED') === 'true';
  }

  evaluate(
    ctx: UserEngagementContext,
    now: Date,
  ): Promise<TriggerCandidate | null> {
    const minAgeHours =
      this.config.get<number>('ENGAGEMENT_UNFINISHED_MIN_AGE_HOURS') ?? 24;
    const threshold =
      this.config.get<number>('ENGAGEMENT_UNFINISHED_PLAN_THRESHOLD') ?? 3;

    const trip = ctx.trips.find(
      (t) =>
        t.status === TripStatus.PLANNING &&
        now.getTime() - t.createdAt.getTime() >= minAgeHours * HOUR_MS &&
        t.planItemCount < threshold,
    );
    if (!trip) return Promise.resolve(null);

    return Promise.resolve({
      trigger: this.trigger,
      tripId: trip.id,
      dedupeKey: `UNFINISHED_PLAN:trip:${trip.id}`,
      hints: {
        cityName: trip.cityName ?? undefined,
        tripName: trip.name,
        planGapCount: trip.planItemCount,
        coarseHint: trip.cityName ?? `trip:${trip.id}`,
      },
      deepLink: { type: ENGAGEMENT_PUSH_TYPE.UNFINISHED_PLAN, tripId: trip.id },
    });
  }
}
