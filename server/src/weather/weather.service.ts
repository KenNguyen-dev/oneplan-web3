import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

export type WeatherBucket = 'HOT' | 'RAIN' | 'COLD' | 'MILD' | 'STORM';

export interface WeatherCondition {
  /** Normalized bucket used by the engagement weather trigger. */
  condition: WeatherBucket;
  tempC: number;
  /** Raw provider condition type, e.g. "THUNDERSTORM" (for hints/debug). */
  rawType: string;
}

interface CachedWeather {
  result: WeatherCondition;
  fetchedAt: Date;
}

// Google Maps Platform Weather API — current conditions.
const API_URL = 'https://weather.googleapis.com/v1/currentConditions:lookup';
const CACHE_TTL_MS = 3 * 60 * 60 * 1000; // 3 hours — weather shifts intra-day
const FETCH_TIMEOUT_MS = 3_000;

/**
 * Current-weather lookups per city, backed by Google Maps Platform Weather API.
 *
 * Modeled on ExchangeRatesService: in-memory Map + `WeatherSnapshot` DB cache
 * (TTL via `fetchedAt`), inflight-coalescing per city, and **never throws** —
 * `getCondition` returns null on any failure (no key, unknown city, API down
 * with no cached row) so the engagement weather trigger simply doesn't fire.
 */
@Injectable()
export class WeatherService {
  private readonly logger = new Logger(WeatherService.name);
  private readonly memoryCache = new Map<number, CachedWeather>();
  private readonly inflight = new Map<number, Promise<void>>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /** Returns the normalized weather condition for a city, or null. */
  async getCondition(cityId: number): Promise<WeatherCondition | null> {
    const now = Date.now();

    const memHit = this.memoryCache.get(cityId);
    if (memHit && now - memHit.fetchedAt.getTime() < CACHE_TTL_MS) {
      return memHit.result;
    }

    const dbHit = await this.readFromDb(cityId);
    if (dbHit && now - dbHit.fetchedAt.getTime() < CACHE_TTL_MS) {
      this.memoryCache.set(cityId, dbHit);
      return dbHit.result;
    }

    if (this.getApiKey()) {
      await this.runInflight(cityId);
      const refreshed = this.memoryCache.get(cityId);
      if (refreshed) return refreshed.result;
    }

    // Live fetch unavailable/failed — fall back to a stale DB row if any.
    return dbHit ? dbHit.result : null;
  }

  // --- internals ---------------------------------------------------------

  private getApiKey(): string {
    return this.config.get<string>('GOOGLE_MAPS_WEATHER_API_KEY') ?? '';
  }

  private hotThreshold(): number {
    return this.config.get<number>('WEATHER_HOT_C') ?? 33;
  }

  private coldThreshold(): number {
    return this.config.get<number>('WEATHER_COLD_C') ?? 12;
  }

  private async readFromDb(cityId: number): Promise<CachedWeather | null> {
    const row = await this.prisma.weatherSnapshot.findUnique({
      where: { cityId },
    });
    if (!row) return null;
    return {
      result: {
        condition: row.condition as WeatherBucket,
        tempC: Number(row.tempC),
        rawType: row.rawType ?? '',
      },
      fetchedAt: row.fetchedAt,
    };
  }

  private async runInflight(cityId: number): Promise<void> {
    const existing = this.inflight.get(cityId);
    if (existing) {
      await existing.catch(() => undefined);
      return;
    }
    const promise = this.fetchAndPersist(cityId);
    this.inflight.set(cityId, promise);
    promise.finally(() => {
      if (this.inflight.get(cityId) === promise) {
        this.inflight.delete(cityId);
      }
    });
    await promise.catch(() => undefined);
  }

  private async fetchAndPersist(cityId: number): Promise<void> {
    const apiKey = this.getApiKey();
    if (!apiKey) return;

    const city = await this.prisma.city.findUnique({
      where: { id: cityId },
      select: { latitude: true, longitude: true },
    });
    if (!city) return;

    const url =
      `${API_URL}?key=${encodeURIComponent(apiKey)}` +
      `&location.latitude=${Number(city.latitude)}` +
      `&location.longitude=${Number(city.longitude)}` +
      `&unitsSystem=METRIC`;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    let response: Response;
    try {
      response = await fetch(url, { signal: controller.signal });
    } catch (err) {
      this.logger.warn(
        `weather fetch failed for city ${cityId}: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return;
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      this.logger.warn(
        `weather API returned HTTP ${response.status} for city ${cityId}`,
      );
      return;
    }

    let body: GoogleWeatherResponse;
    try {
      body = (await response.json()) as GoogleWeatherResponse;
    } catch {
      this.logger.warn(`weather API returned invalid JSON for city ${cityId}`);
      return;
    }

    const tempC = body.temperature?.degrees;
    const rawType = body.weatherCondition?.type ?? '';
    if (typeof tempC !== 'number' || !Number.isFinite(tempC)) {
      this.logger.warn(`weather API missing temperature for city ${cityId}`);
      return;
    }

    const condition = this.classify(rawType, tempC);
    const result: WeatherCondition = { condition, tempC, rawType };
    const fetchedAt = new Date();

    try {
      await this.prisma.weatherSnapshot.upsert({
        where: { cityId },
        update: {
          tempC: new Prisma.Decimal(tempC),
          condition,
          rawType,
          payload: body as unknown as Prisma.InputJsonValue,
          fetchedAt,
        },
        create: {
          cityId,
          tempC: new Prisma.Decimal(tempC),
          condition,
          rawType,
          payload: body as unknown as Prisma.InputJsonValue,
          fetchedAt,
        },
      });
    } catch (err) {
      this.logger.warn(
        `Failed to persist weather for city ${cityId}: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      // Still serve the freshly-fetched value from memory below.
    }

    this.memoryCache.set(cityId, { result, fetchedAt });
  }

  /**
   * Map a Google condition `type` + temperature to a normalized bucket.
   * Precedence: storm > rain > snow/cold > hot > mild. Only HOT/RAIN/STORM
   * fire the engagement trigger; COLD/MILD are intentionally quiet.
   */
  classify(rawType: string, tempC: number): WeatherBucket {
    const t = rawType.toUpperCase();
    if (/THUNDER|SNOWSTORM|HAIL/.test(t)) return 'STORM';
    if (/SNOW/.test(t)) return tempC >= this.hotThreshold() ? 'HOT' : 'COLD';
    if (/RAIN|SHOWERS/.test(t)) return 'RAIN';
    if (tempC >= this.hotThreshold()) return 'HOT';
    if (tempC <= this.coldThreshold()) return 'COLD';
    return 'MILD';
  }
}

interface GoogleWeatherResponse {
  temperature?: { degrees?: number; unit?: string };
  weatherCondition?: { type?: string; description?: { text?: string } };
}
