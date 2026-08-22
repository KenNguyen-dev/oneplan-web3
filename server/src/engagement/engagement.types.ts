import {
  EngagementLocale,
  EngagementTrigger,
  TripStatus,
} from '@prisma/client';

/** A user's non-ENDED trip with the bits triggers care about. */
export interface TripContext {
  id: number;
  status: TripStatus;
  name: string;
  cityId: number | null;
  cityName: string | null;
  countryId: number | null;
  countryTimezones: string | null;
  planItemCount: number;
  createdAt: Date;
}

/** Everything an evaluator needs about one candidate user, loaded in batch. */
export interface UserEngagementContext {
  userId: number;
  locale: EngagementLocale;
  lastSessionAt: Date | null;
  trips: TripContext[];
}

/** Grounding facts passed to the LLM / static template. */
export interface CopyHints {
  cityName?: string;
  tripName?: string;
  weatherHint?: string;
  tempC?: number;
  planGapCount?: number;
  listingName?: string;
  /** Coarse, low-cardinality key for the generation cache (e.g. "HOT:Saigon"). */
  coarseHint: string;
}

export interface DeepLinkTarget {
  type: string;
  tripId?: number;
  listingId?: number;
}

/** A trigger's verdict for a user: send this push, deduped by `dedupeKey`. */
export interface TriggerCandidate {
  trigger: EngagementTrigger;
  tripId?: number;
  listingId?: number;
  dedupeKey: string;
  hints: CopyHints;
  deepLink: DeepLinkTarget;
}

export interface GeneratedCopy {
  title: string;
  body: string;
  usedLlm: boolean;
}

export interface TriggerEvaluator {
  readonly trigger: EngagementTrigger;
  /** Honors the per-trigger ENGAGEMENT_TRIGGER_* feature flag. */
  isEnabled(): boolean;
  evaluate(
    ctx: UserEngagementContext,
    now: Date,
  ): Promise<TriggerCandidate | null>;
}

export const ENGAGEMENT_EVALUATORS = Symbol('ENGAGEMENT_EVALUATORS');
