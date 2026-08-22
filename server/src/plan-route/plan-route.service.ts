import { createHash } from 'crypto';
import { ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InviteStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { PlanRouteDto } from './dto/plan-route.dto';
import { PlanRouteLegDto } from './dto/plan-route-leg.dto';
import { PlanRoutePinDto } from './dto/plan-route-pin.dto';

const ROUTES_API_URL =
  'https://routes.googleapis.com/directions/v2:computeRoutes';
const FIELD_MASK =
  'routes.legs.polyline.encodedPolyline,routes.legs.duration,routes.legs.distanceMeters';
const FETCH_TIMEOUT_MS = 5_000;
// Routes API Essentials tier caps at 10 intermediates (12 pins per request,
// origin + destination + 10 intermediates). Staying under this avoids the
// Pro-tier SKU.
const MAX_PINS_PER_CHUNK = 12;

interface LocatedPlanItem {
  id: number;
  title: string;
  latitude: number;
  longitude: number;
  location: string | null;
  startTime: string | null;
  sortOrder: number;
}

/**
 * Server-side day-route endpoint (Routes API + geometry cache).
 *
 * Mirrors ExchangeRatesService/WeatherService conventions: own external key
 * (optional — falls back to null legs, never throws), own DB cache, never
 * caches a failure.
 */
@Injectable()
export class PlanRouteService {
  private readonly logger = new Logger(PlanRouteService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async getPlanRoute(
    tripId: number,
    userId: number,
    date: string,
  ): Promise<PlanRouteDto> {
    await this.assertMember(tripId, userId);

    const pins = await this.derivePins(tripId, date);

    if (pins.length < 2) {
      return { pins, legs: [] };
    }

    const apiKey = this.getApiKey();
    if (!apiKey) {
      return { pins, legs: straightLineLegs(pins.length) };
    }

    const routeHash = computeRouteHash(pins);
    const cached = await this.prisma.planRouteCache.findUnique({
      where: { routeHash },
    });
    if (cached) {
      return { pins, legs: cached.payload as unknown as PlanRouteLegDto[] };
    }

    const legs = await this.computeLegs(pins, apiKey);
    if (!legs) {
      // Upstream failure — pins still render, legs fall back to straight
      // lines. Never cache a failure.
      return { pins, legs: straightLineLegs(pins.length) };
    }

    try {
      await this.prisma.planRouteCache.create({
        data: { routeHash, payload: legs as unknown as object },
      });
    } catch (err) {
      // Cache is best-effort (e.g. a racing duplicate insert on routeHash).
      this.logger.warn(
        `Failed to persist plan-route cache for hash ${routeHash}: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    }

    return { pins, legs };
  }

  // --- pin derivation ------------------------------------------------------

  private async derivePins(
    tripId: number,
    date: string,
  ): Promise<PlanRoutePinDto[]> {
    const items = await this.prisma.tripPlanItem.findMany({
      where: { tripId, planDate: new Date(date) },
      select: {
        id: true,
        title: true,
        latitude: true,
        longitude: true,
        location: true,
        startTime: true,
        sortOrder: true,
      },
    });

    const located: LocatedPlanItem[] = items
      .filter((item) => item.latitude !== null && item.longitude !== null)
      .map((item) => ({
        id: item.id,
        title: item.title,
        latitude: item.latitude as number,
        longitude: item.longitude as number,
        location: item.location,
        startTime: item.startTime,
        sortOrder: item.sortOrder,
      }));

    const timed = located
      .filter((item) => item.startTime !== null)
      .sort((a, b) => {
        if (a.startTime !== b.startTime) {
          return a.startTime! < b.startTime! ? -1 : 1;
        }
        if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
        return a.id - b.id;
      });

    const untimed = located
      .filter((item) => item.startTime === null)
      .sort((a, b) => {
        if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
        return a.id - b.id;
      });

    return [...timed, ...untimed].map((item, offset) => ({
      id: item.id,
      index: offset + 1,
      title: item.title,
      latitude: item.latitude,
      longitude: item.longitude,
      subtitle: item.location,
      timeLabel: item.startTime,
    }));
  }

  // --- Routes API ------------------------------------------------------

  private async computeLegs(
    pins: PlanRoutePinDto[],
    apiKey: string,
  ): Promise<PlanRouteLegDto[] | null> {
    const chunks = chunkPins(pins, MAX_PINS_PER_CHUNK);
    const legs: PlanRouteLegDto[] = [];

    for (const chunk of chunks) {
      const chunkLegs = await this.callRoutesApi(chunk, apiKey);
      if (!chunkLegs) return null;
      legs.push(...chunkLegs);
    }

    if (legs.length !== pins.length - 1) {
      this.logger.error(
        `Routes API stitching mismatch: expected ${pins.length - 1} legs, got ${legs.length}`,
      );
      return null;
    }

    return legs;
  }

  private async callRoutesApi(
    chunk: PlanRoutePinDto[],
    apiKey: string,
  ): Promise<PlanRouteLegDto[] | null> {
    const body = {
      origin: pointOf(chunk[0]),
      destination: pointOf(chunk[chunk.length - 1]),
      intermediates: chunk.slice(1, -1).map(pointOf),
      travelMode: 'DRIVE',
    };

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    let response: Response;
    try {
      response = await fetch(ROUTES_API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': FIELD_MASK,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } catch (err) {
      this.logger.warn(
        `Routes API fetch failed: ${err instanceof Error ? err.message : String(err)}`,
      );
      return null;
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      this.logger.warn(`Routes API returned HTTP ${response.status}`);
      return null;
    }

    let payload: {
      routes?: Array<{
        legs?: Array<{
          polyline?: { encodedPolyline?: string };
          duration?: string;
          distanceMeters?: number;
        }>;
      }>;
    };
    try {
      payload = await response.json();
    } catch (err) {
      this.logger.warn(
        `Routes API returned invalid JSON: ${err instanceof Error ? err.message : String(err)}`,
      );
      return null;
    }

    const routeLegs = payload.routes?.[0]?.legs;
    if (!routeLegs || routeLegs.length !== chunk.length - 1) {
      this.logger.warn(
        `Routes API returned ${routeLegs?.length ?? 0} legs for a ${chunk.length}-pin chunk`,
      );
      return null;
    }

    return routeLegs.map((leg) => ({
      polyline: leg.polyline?.encodedPolyline ?? null,
      durationSec: leg.duration ? parseDurationSeconds(leg.duration) : null,
      distanceM: leg.distanceMeters ?? null,
    }));
  }

  private getApiKey(): string {
    return this.config.get<string>('GOOGLE_ROUTES_API_KEY') ?? '';
  }

  private async assertMember(tripId: number, userId: number): Promise<void> {
    const member = await this.prisma.tripMember.findUnique({
      where: { tripId_userId: { tripId, userId } },
    });

    if (!member || member.inviteStatus !== InviteStatus.ACCEPTED) {
      throw new ForbiddenException('You are not a member of this trip');
    }
  }
}

function pointOf(pin: PlanRoutePinDto) {
  return {
    location: {
      latLng: { latitude: pin.latitude, longitude: pin.longitude },
    },
  };
}

/** e.g. "723s" -> 723; malformed values fall back to null. */
function parseDurationSeconds(duration: string): number | null {
  const match = /^(\d+)s$/.exec(duration);
  return match ? Number(match[1]) : null;
}

function straightLineLegs(pinCount: number): PlanRouteLegDto[] {
  return Array.from({ length: Math.max(0, pinCount - 1) }, () => ({
    polyline: null,
    durationSec: null,
    distanceM: null,
  }));
}

/**
 * SHA-256 of the ordered coordinates (rounded to 6dp) + travel mode.
 * Renaming/retiming a stop doesn't change this hash — only coordinate
 * changes (add/remove/move/reorder a stop) do, so the cache is
 * self-invalidating without any write-path hook.
 */
function computeRouteHash(pins: PlanRoutePinDto[]): string {
  const material =
    pins
      .map((p) => `${p.latitude.toFixed(6)},${p.longitude.toFixed(6)}`)
      .join('|') + '|DRIVE';
  return createHash('sha256').update(material).digest('hex');
}

/**
 * Splits pins into chunks of at most `maxSize`, each chunk overlapping the
 * previous one by exactly one pin (the chunk boundary), so that stitching
 * each chunk's `length - 1` legs back together never drops the leg spanning
 * a chunk boundary. Total legs across all chunks == pins.length - 1.
 */
function chunkPins<T>(pins: T[], maxSize: number): T[][] {
  if (pins.length <= maxSize) return [pins];

  const chunks: T[][] = [];
  let start = 0;
  while (start < pins.length - 1) {
    const end = Math.min(start + maxSize, pins.length);
    chunks.push(pins.slice(start, end));
    if (end >= pins.length) break;
    start = end - 1;
  }
  return chunks;
}
