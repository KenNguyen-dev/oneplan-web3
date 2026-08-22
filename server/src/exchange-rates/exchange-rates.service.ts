import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Currency, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { getStaticFallbackRate } from './static-fallback-rates';

export interface RateResult {
  rate: Prisma.Decimal;
  fetchedAt: Date;
  isStale: boolean;
}

interface CachedRate {
  rate: Prisma.Decimal;
  fetchedAt: Date;
}

interface ExchangeRateApiResponse {
  result: 'success' | 'error';
  'error-type'?: string;
  base_code?: string;
  conversion_rates?: Record<string, number>;
}

const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
const FETCH_TIMEOUT_MS = 3_000;
const API_BASE_URL = 'https://v6.exchangerate-api.com/v6';
const SUPPORTED_CURRENCIES = Object.values(Currency);

/**
 * Fetches and caches exchange rates between the 10 supported `Currency`
 * enum values.
 *
 * Resolution order in `getRate(from, to)`:
 *   1. from === to → { rate: 1, isStale: false } (no IO)
 *   2. in-memory cache, fresh (<24h)
 *   3. DB cache, fresh (<24h) → promote to memory
 *   4. inflight dedup → live fetch → batched upsert of all 9 pairs
 *   5. on fetch failure, return newest DB row (any age) with isStale: true
 *   6. no DB row anywhere → static fallback with isStale: true
 *
 * This service NEVER throws from `getRate` — a rate is always returned.
 *
 * Batched fetch: a single `/latest/{BASE}` call populates all 9 pairs
 * (BASE → every other supported currency) in one transaction. This keeps
 * us well under the 1,500 req/month free-tier limit.
 */
@Injectable()
export class ExchangeRatesService implements OnModuleInit {
  private readonly logger = new Logger(ExchangeRatesService.name);
  private readonly memoryCache = new Map<string, CachedRate>();
  private readonly inflight = new Map<string, Promise<void>>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  onModuleInit(): void {
    const key = this.getApiKey();
    if (!key && process.env.NODE_ENV !== 'test') {
      this.logger.warn(
        'EXCHANGERATE_API_KEY is not set. Exchange rates will be served from DB cache or static fallback only.',
      );
    }
  }

  /**
   * Returns the exchange rate for converting from `from` to `to`.
   *
   * Multiply an amount in `from` by the returned rate to get the equivalent
   * amount in `to`. Never throws — on any failure, returns a static fallback
   * rate with `isStale: true`.
   */
  async getRate(from: Currency, to: Currency): Promise<RateResult> {
    if (from === to) {
      return {
        rate: new Prisma.Decimal(1),
        fetchedAt: new Date(),
        isStale: false,
      };
    }

    const now = Date.now();

    // 2. In-memory cache hit
    const memHit = this.memoryCache.get(cacheKey(from, to));
    if (memHit && now - memHit.fetchedAt.getTime() < CACHE_TTL_MS) {
      return { ...memHit, isStale: false };
    }

    // 3. DB cache hit
    const dbHit = await this.readFromDb(from, to);
    if (dbHit && now - dbHit.fetchedAt.getTime() < CACHE_TTL_MS) {
      this.memoryCache.set(cacheKey(from, to), dbHit);
      return { ...dbHit, isStale: false };
    }

    // 4. Attempt live fetch (coalesced by base currency — a single
    // /latest/{BASE} call covers all 9 target pairs).
    if (this.getApiKey()) {
      await this.runInflight(from);

      // After the fetch settles, try memory then DB again.
      const refreshedMem = this.memoryCache.get(cacheKey(from, to));
      if (refreshedMem) {
        return { ...refreshedMem, isStale: false };
      }
      const refreshedDb = await this.readFromDb(from, to);
      if (refreshedDb) {
        this.memoryCache.set(cacheKey(from, to), refreshedDb);
        // Don't mark fresh here — readFromDb returns the newest row, but
        // we got here because the earlier read was stale, so this row
        // might still be stale. Check freshness explicitly.
        const isStale =
          Date.now() - refreshedDb.fetchedAt.getTime() >= CACHE_TTL_MS;
        return { ...refreshedDb, isStale };
      }
    }

    // 5. Fell through live fetch — return stale DB row if any
    if (dbHit) {
      return { ...dbHit, isStale: true };
    }

    // 6. Static fallback
    return {
      rate: new Prisma.Decimal(getStaticFallbackRate(from, to)),
      fetchedAt: new Date(0),
      isStale: true,
    };
  }

  /**
   * Convert an amount from `from` currency to `to` (home) currency.
   *
   * Returns the converted amount as a `Prisma.Decimal`. Never throws — the
   * rate used will be stale-fallback before this method throws.
   */
  async convertToHome(
    amount: Prisma.Decimal,
    from: Currency,
    to: Currency,
  ): Promise<Prisma.Decimal> {
    const { rate } = await this.getRate(from, to);
    return amount.mul(rate);
  }

  // --- internals ---------------------------------------------------------

  private getApiKey(): string {
    return this.config.get<string>('EXCHANGERATE_API_KEY') ?? '';
  }

  private async readFromDb(
    from: Currency,
    to: Currency,
  ): Promise<CachedRate | null> {
    const row = await this.prisma.exchangeRate.findUnique({
      where: {
        fromCurrency_toCurrency: {
          fromCurrency: from,
          toCurrency: to,
        },
      },
    });
    if (!row) return null;
    return { rate: row.rate, fetchedAt: row.fetchedAt };
  }

  /**
   * Run (or join) a coalesced live fetch keyed by the base currency.
   *
   * A single /latest/{base} call populates ALL pairs from that base, so we
   * only need one inflight entry per `from` currency even if the caller is
   * asking for many different `to` pairs at once.
   */
  private async runInflight(from: Currency): Promise<void> {
    const key = from;
    const existing = this.inflight.get(key);
    if (existing) {
      await existing.catch(() => undefined);
      return;
    }

    const promise = this.fetchAndPersist(from);
    this.inflight.set(key, promise);
    // Identity-guarded cleanup: only clear the map entry if it still points
    // at THIS promise. Prevents a rare race where a late-arriving caller
    // would otherwise miss the dedup window between the `.finally` firing
    // and earlier awaiters resuming.
    promise.finally(() => {
      if (this.inflight.get(key) === promise) {
        this.inflight.delete(key);
      }
    });
    await promise.catch(() => undefined);
  }

  private async fetchAndPersist(from: Currency): Promise<void> {
    const apiKey = this.getApiKey();
    if (!apiKey) return;

    const url = `${API_BASE_URL}/${apiKey}/latest/${from}`;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    let response: Response;
    try {
      response = await fetch(url, { signal: controller.signal });
    } catch (err) {
      this.logger.warn(
        `exchangerate-api fetch failed for base ${from}: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return;
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      this.logger.warn(
        `exchangerate-api returned HTTP ${response.status} for base ${from}`,
      );
      return;
    }

    let body: ExchangeRateApiResponse;
    try {
      body = (await response.json()) as ExchangeRateApiResponse;
    } catch (err) {
      this.logger.warn(
        `exchangerate-api returned invalid JSON for base ${from}: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return;
    }

    if (body.result !== 'success' || !body.conversion_rates) {
      this.logger.warn(
        `exchangerate-api returned error for base ${from}: ${
          body['error-type'] ?? 'unknown'
        }`,
      );
      return;
    }

    const fetchedAt = new Date();
    const rows: Array<{ to: Currency; rate: string }> = [];
    for (const target of SUPPORTED_CURRENCIES) {
      if (target === from) continue;
      const rawRate = body.conversion_rates[target];
      if (typeof rawRate !== 'number' || !Number.isFinite(rawRate)) continue;
      rows.push({ to: target, rate: rawRate.toString() });
    }

    if (rows.length === 0) return;

    try {
      await this.prisma.$transaction(
        rows.map((row) =>
          this.prisma.exchangeRate.upsert({
            where: {
              fromCurrency_toCurrency: {
                fromCurrency: from,
                toCurrency: row.to,
              },
            },
            update: { rate: row.rate, fetchedAt },
            create: {
              fromCurrency: from,
              toCurrency: row.to,
              rate: row.rate,
              fetchedAt,
            },
          }),
        ),
      );
    } catch (err) {
      this.logger.warn(
        `Failed to persist exchange rates for base ${from}: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return;
    }

    // Promote all rows to memory cache.
    for (const row of rows) {
      this.memoryCache.set(cacheKey(from, row.to), {
        rate: new Prisma.Decimal(row.rate),
        fetchedAt,
      });
    }
  }
}

function cacheKey(from: Currency, to: Currency): string {
  return `${from}_${to}`;
}
