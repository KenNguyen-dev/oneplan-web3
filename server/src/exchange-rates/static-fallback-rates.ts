import { Currency } from '@prisma/client';

/**
 * Approximate rates relative to USD.
 *
 * Last updated: 2026-04-21. Refresh annually.
 *
 * These are used ONLY when neither a live fetch nor a cached DB row is
 * available (e.g. first boot with no API key). Any rate derived from this
 * table is always returned with `isStale: true` so clients can surface a
 * warning in the UI.
 */
const USD_RATES: Record<Currency, number> = {
  USD: 1.0,
  EUR: 0.92,
  VND: 24500,
  THB: 36.5,
  KRW: 1360,
  JPY: 152,
  CNY: 7.2,
  TWD: 32.1,
  SGD: 1.35,
  MYR: 4.7,
};

/**
 * Compute a fallback rate for (from → to) by bridging through USD.
 *
 * rate(from → to) = USD_RATES[to] / USD_RATES[from]
 *
 * Returns 1 for same-currency pairs.
 */
export function getStaticFallbackRate(from: Currency, to: Currency): number {
  if (from === to) return 1;
  const fromRate = USD_RATES[from];
  const toRate = USD_RATES[to];
  // Defensive: should never happen since the map covers all Currency values.
  // Explicit null/undefined check (not a falsy check) so a future `0`
  // placeholder entry surfaces loudly (as a divide-by-zero) instead of
  // silently returning 1 and hiding the misconfiguration.
  if (fromRate == null || toRate == null) return 1;
  return toRate / fromRate;
}
