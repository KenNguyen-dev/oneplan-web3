import { ConfigService } from '@nestjs/config';
import { EngagementLocale, TripStatus } from '@prisma/client';
import { UnfinishedPlanEvaluator } from './unfinished-plan.evaluator';
import { UserEngagementContext } from '../engagement.types';

function makeConfig(): ConfigService {
  return {
    get: (key: string) => {
      switch (key) {
        case 'ENGAGEMENT_TRIGGER_UNFINISHED':
          return 'true';
        case 'ENGAGEMENT_UNFINISHED_MIN_AGE_HOURS':
          return 24;
        case 'ENGAGEMENT_UNFINISHED_PLAN_THRESHOLD':
          return 3;
        default:
          return undefined;
      }
    },
  } as unknown as ConfigService;
}

function ctxWithTrip(
  overrides: Partial<{
    status: TripStatus;
    planItemCount: number;
    createdAt: Date;
  }>,
): UserEngagementContext {
  return {
    userId: 7,
    locale: EngagementLocale.EN,
    lastSessionAt: new Date(),
    trips: [
      {
        id: 42,
        status: overrides.status ?? TripStatus.PLANNING,
        name: 'Da Lat',
        cityId: 88,
        cityName: 'Da Lat',
        countryId: 1,
        countryTimezones: '[{"zoneName":"Asia/Ho_Chi_Minh"}]',
        planItemCount: overrides.planItemCount ?? 1,
        createdAt:
          overrides.createdAt ?? new Date(Date.now() - 48 * 60 * 60 * 1000),
      },
    ],
  };
}

describe('UnfinishedPlanEvaluator', () => {
  const now = new Date();
  const ev = new UnfinishedPlanEvaluator(makeConfig());

  it('fires for an aged PLANNING trip with a sparse plan', async () => {
    const result = await ev.evaluate(ctxWithTrip({}), now);
    expect(result).not.toBeNull();
    expect(result?.dedupeKey).toBe('UNFINISHED_PLAN:trip:42');
    expect(result?.tripId).toBe(42);
    expect(result?.deepLink.type).toBe('engagement_unfinished_plan');
  });

  it('does not fire when the plan already has enough items', async () => {
    const result = await ev.evaluate(ctxWithTrip({ planItemCount: 5 }), now);
    expect(result).toBeNull();
  });

  it('does not fire for a just-created trip (below min age)', async () => {
    const result = await ev.evaluate(
      ctxWithTrip({ createdAt: new Date(Date.now() - 60 * 60 * 1000) }),
      now,
    );
    expect(result).toBeNull();
  });

  it('does not fire for ONGOING/ENDED trips', async () => {
    const result = await ev.evaluate(
      ctxWithTrip({ status: TripStatus.ONGOING }),
      now,
    );
    expect(result).toBeNull();
  });
});
