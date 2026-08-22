import { Currency } from '@prisma/client';

const ISO_MAP: Record<string, Currency> = {
  USD: Currency.USD,
  EUR: Currency.EUR,
  VND: Currency.VND,
  THB: Currency.THB,
  KRW: Currency.KRW,
  JPY: Currency.JPY,
  CNY: Currency.CNY,
  TWD: Currency.TWD,
  SGD: Currency.SGD,
  MYR: Currency.MYR,
};

/**
 * Map a free-text `Country.currency` string to a `Currency` enum value.
 *
 * The `Country.currency` column is a `VARCHAR(255)` of arbitrary free-text
 * (e.g. `"THB"`, `"Thai Baht"`, `"USD, EUR"`, `"Hong Kong dollar (HKD)"`).
 * This helper splits the input on non-word characters, uppercases each
 * token, and returns the first token that matches one of the 10 supported
 * currencies.
 *
 * Returns `null` if no token matches. Never throws.
 */
export function mapIsoToCurrencyEnum(iso?: string | null): Currency | null {
  if (!iso) return null;
  // Split on any non-word char (spaces, commas, parens, slashes, etc.)
  const tokens = iso.split(/[^A-Za-z]+/).filter(Boolean);
  for (const token of tokens) {
    const upper = token.toUpperCase();
    if (upper in ISO_MAP) {
      return ISO_MAP[upper];
    }
  }
  return null;
}
