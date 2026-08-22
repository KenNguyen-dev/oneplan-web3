import { Injectable, Logger } from '@nestjs/common';
import { EngagementLocale, EngagementTrigger } from '@prisma/client';
import { GeminiService } from '../common/gemini/gemini.service';
import {
  MAX_BODY_LEN,
  MAX_TITLE_LEN,
  staticCopy,
} from './engagement.constants';
import { GeneratedCopy, TriggerCandidate } from './engagement.types';

// Vertex Gemini 2.5 Flash routinely needs more than a few seconds (it spends
// reasoning tokens before emitting), so a tight timeout aborts every call and
// forces the static fallback. The per-cohort generation cache amortizes this —
// only the first user of each (trigger, locale, hint) cohort waits.
const LLM_TIMEOUT_MS = 20_000;
const GEN_CACHE_TTL_MS = 6 * 60 * 60 * 1000; // 6h — many users share a cohort

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    title: { type: 'STRING' },
    body: { type: 'STRING' },
  },
  required: ['title', 'body'],
};

interface CachedCopy {
  copy: { title: string; body: string };
  at: number;
}

/**
 * Generates the engagement push copy. Tries Gemini (grounded in the trip's
 * real context, in the user's language), and falls back to a static template
 * on ANY failure — the pipeline never blocks on the LLM.
 *
 * A coarse in-memory cache (keyed by trigger + locale + coarse hint, e.g.
 * "WEATHER:VN:HOT:Saigon") means one Gemini call serves a whole city/weather
 * cohort per window; per-user uniqueness is still guaranteed downstream by the
 * EngagementNotification dedupeKey.
 */
@Injectable()
export class EngagementCopyService {
  private readonly logger = new Logger(EngagementCopyService.name);
  private readonly cache = new Map<string, CachedCopy>();

  constructor(private readonly gemini: GeminiService) {}

  async generate(
    candidate: TriggerCandidate,
    locale: EngagementLocale,
  ): Promise<GeneratedCopy> {
    const cacheKey = `${candidate.trigger}:${locale}:${candidate.hints.coarseHint}`;
    const cached = this.cache.get(cacheKey);
    if (cached && Date.now() - cached.at < GEN_CACHE_TTL_MS) {
      return { ...cached.copy, usedLlm: true };
    }

    const llm = await this.tryLlm(candidate, locale);
    if (llm) {
      this.cache.set(cacheKey, { copy: llm, at: Date.now() });
      return { ...llm, usedLlm: true };
    }

    const fallback = staticCopy(candidate.trigger, locale, candidate.hints);
    return { ...fallback, usedLlm: false };
  }

  private async tryLlm(
    candidate: TriggerCandidate,
    locale: EngagementLocale,
  ): Promise<{ title: string; body: string } | null> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), LLM_TIMEOUT_MS);
    try {
      const result = await this.gemini.generateJsonFromText<{
        title?: unknown;
        body?: unknown;
      }>({
        prompt: this.buildPrompt(candidate, locale),
        responseSchema: RESPONSE_SCHEMA,
        signal: controller.signal,
        temperature: 0.9,
      });

      const title = typeof result.title === 'string' ? result.title.trim() : '';
      const body = typeof result.body === 'string' ? result.body.trim() : '';
      if (!title || !body) return null;

      return {
        title: title.slice(0, MAX_TITLE_LEN),
        body: body.slice(0, MAX_BODY_LEN),
      };
    } catch (err) {
      this.logger.warn(
        `LLM copy generation failed (${candidate.trigger}); using static template: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return null;
    } finally {
      clearTimeout(timeout);
    }
  }

  private buildPrompt(
    candidate: TriggerCandidate,
    locale: EngagementLocale,
  ): string {
    const language = locale === EngagementLocale.VN ? 'Vietnamese' : 'English';
    const grounding: Record<string, unknown> = {
      trigger: this.triggerDescription(candidate.trigger),
    };
    const h = candidate.hints;
    if (h.cityName) grounding.city = h.cityName;
    if (h.tripName) grounding.tripName = h.tripName;
    if (h.weatherHint) grounding.weather = h.weatherHint;
    if (typeof h.tempC === 'number')
      grounding.temperatureC = Math.round(h.tempC);
    if (typeof h.planGapCount === 'number')
      grounding.planItemsSoFar = h.planGapCount;
    if (h.listingName) grounding.newPlanName = h.listingName;

    return [
      `You write ONE short, friendly mobile push notification for a group trip-planning app.`,
      `Output JSON: {"title": string, "body": string}.`,
      `Language: ${language}.`,
      `Title <= ${MAX_TITLE_LEN} characters. Body <= ${MAX_BODY_LEN} characters.`,
      `Be warm, concrete, and casual — one single idea. No emoji spam (at most one).`,
      `Only use the place/plan names provided below. Do NOT invent place names, prices, or facts.`,
      `Context: ${JSON.stringify(grounding)}`,
    ].join('\n');
  }

  private triggerDescription(trigger: EngagementTrigger): string {
    switch (trigger) {
      case EngagementTrigger.UNFINISHED_PLAN:
        return 'The user created a trip but the plan is nearly empty — nudge them to add interesting spots.';
      case EngagementTrigger.WEATHER:
        return 'Use the current weather to suggest the user plan something fitting for their trip city.';
      case EngagementTrigger.DORMANT:
        return "The user hasn't opened the app in a while — gently invite them back to keep planning.";
      case EngagementTrigger.NEW_PLAN_AVAILABLE:
        return 'A relevant new trip plan is available on the marketplace for their destination.';
      default:
        return 'Encourage the user to keep planning their trip.';
    }
  }
}
