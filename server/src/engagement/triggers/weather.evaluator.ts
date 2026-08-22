import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { EngagementTrigger, TripStatus } from '@prisma/client';
import { WeatherBucket, WeatherService } from '../../weather/weather.service';
import { ENGAGEMENT_PUSH_TYPE } from '../engagement.constants';
import {
  TriggerCandidate,
  TriggerEvaluator,
  UserEngagementContext,
} from '../engagement.types';
import { ymdKey } from '../engagement.util';

const FIRING: WeatherBucket[] = ['HOT', 'RAIN', 'STORM'];

const WEATHER_HINTS: Record<string, string> = {
  HOT: "it's hot today — suggest something cooling like a beach, water spot, or somewhere with shade/AC",
  RAIN: "it's rainy — suggest a cozy indoor spot like a cafe, museum, or covered market",
  STORM: "there's a storm — suggest staying in and planning indoor activities",
};

/**
 * Weather-aware nudge for a user's upcoming/ongoing trip city. Keyed per user
 * per city per day so other users in the same city still get their own push.
 */
@Injectable()
export class WeatherEvaluator implements TriggerEvaluator {
  readonly trigger = EngagementTrigger.WEATHER;

  constructor(
    private readonly config: ConfigService,
    private readonly weather: WeatherService,
  ) {}

  isEnabled(): boolean {
    return this.config.get<string>('ENGAGEMENT_TRIGGER_WEATHER') === 'true';
  }

  async evaluate(
    ctx: UserEngagementContext,
    now: Date,
  ): Promise<TriggerCandidate | null> {
    for (const trip of ctx.trips) {
      if (trip.cityId == null) continue;
      if (
        trip.status !== TripStatus.PLANNING &&
        trip.status !== TripStatus.ONGOING
      ) {
        continue;
      }

      const w = await this.weather.getCondition(trip.cityId);
      if (!w || !FIRING.includes(w.condition)) continue;

      return {
        trigger: this.trigger,
        tripId: trip.id,
        dedupeKey: `WEATHER:user:${ctx.userId}:city:${trip.cityId}:${ymdKey(now)}`,
        hints: {
          cityName: trip.cityName ?? undefined,
          tripName: trip.name,
          weatherHint: WEATHER_HINTS[w.condition],
          tempC: w.tempC,
          coarseHint: `${w.condition}:${trip.cityName ?? trip.cityId}`,
        },
        deepLink: { type: ENGAGEMENT_PUSH_TYPE.WEATHER, tripId: trip.id },
      };
    }
    return null;
  }
}
