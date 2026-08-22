import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

// Travelpayouts (Aviasales) cached-price API client.
// Docs: https://travelpayouts.github.io/slate/ (Data API v3).
// Prices are CACHED search results (minutes to hours old), which is exactly
// why the engine runs a verify pass before alerting anyone.

const API_BASE = 'https://api.travelpayouts.com/aviasales/v3/prices_for_dates';
const BOOKING_BASE = 'https://www.aviasales.com';

export interface FarePrice {
  origin: string;
  destination: string;
  departDate: string; // YYYY-MM-DD
  departAt: string | null; // full ISO datetime when the source carries it
  durationMin: number | null;
  airline: string;
  price: number; // VND
  link: string | null; // absolute booking URL with our marker
  foundAt: string;
}

interface TpRow {
  origin?: string;
  destination?: string;
  departure_at?: string;
  duration?: number;
  airline?: string;
  price?: number;
  link?: string;
  found_at?: string;
}

@Injectable()
export class TravelpayoutsService {
  private readonly logger = new Logger(TravelpayoutsService.name);

  constructor(private readonly config: ConfigService) {}

  get enabled(): boolean {
    return Boolean(this.config.get<string>('TRAVELPAYOUTS_TOKEN'));
  }

  private get marker(): string {
    return this.config.get<string>('TRAVELPAYOUTS_MARKER') ?? '';
  }

  // Cheapest cached fares for one route and one month (YYYY-MM), one row per
  // departure date. One call covers every order watching that route/month.
  async pricesForMonth(
    origin: string,
    destination: string,
    month: string,
  ): Promise<FarePrice[]> {
    const token = this.config.get<string>('TRAVELPAYOUTS_TOKEN');
    if (!token) return [];
    const qs = new URLSearchParams({
      origin,
      destination,
      currency: 'vnd',
      departure_at: month,
      one_way: 'true',
      sorting: 'price',
      limit: '100',
    });
    try {
      const r = await fetch(`${API_BASE}?${qs.toString()}`, {
        headers: { 'X-Access-Token': token },
        signal: AbortSignal.timeout(20_000),
      });
      if (!r.ok) {
        this.logger.warn(
          `TP ${origin}-${destination} ${month}: HTTP ${r.status}`,
        );
        return [];
      }
      const data = (await r.json()) as { data?: TpRow[] };
      return (data.data ?? [])
        .filter((x) => x.price && x.departure_at)
        .map((x) => ({
          origin: x.origin ?? origin,
          destination: x.destination ?? destination,
          departDate: (x.departure_at as string).slice(0, 10),
          departAt:
            (x.departure_at as string).length > 10
              ? (x.departure_at as string)
              : null,
          durationMin: x.duration ?? null,
          airline: x.airline ?? '??',
          price: x.price as number,
          link: x.link ? this.bookingLink(x.link) : null,
          foundAt: x.found_at ?? '',
        }));
    } catch (e) {
      this.logger.warn(
        `TP ${origin}-${destination} ${month}: ${(e as Error).message}`,
      );
      return [];
    }
  }

  // Verify pass: re-fetch the route for the exact date right before alerting.
  // Same cached API, but a fresh call: if the deal vanished from the cache the
  // price will have moved and the alert is suppressed.
  async priceForDate(
    origin: string,
    destination: string,
    date: string,
  ): Promise<FarePrice | null> {
    const month = date.slice(0, 7);
    const rows = await this.pricesForMonth(origin, destination, month);
    return rows.find((r) => r.departDate === date) ?? null;
  }

  // TP returns a relative search link; attach the host and our marker so the
  // booking is attributed. The link already carries a query string.
  bookingLink(relative: string): string {
    const abs = relative.startsWith('http')
      ? relative
      : `${BOOKING_BASE}${relative}`;
    if (!this.marker) return abs;
    return abs.includes('marker=')
      ? abs
      : `${abs}${abs.includes('?') ? '&' : '?'}marker=${this.marker}`;
  }
}
