import { ConfigService } from '@nestjs/config';
import { ForbiddenException } from '@nestjs/common';
import { InviteStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { PlanRouteService } from './plan-route.service';

const DATE = '2026-07-20';
const API_KEY = 'test-routes-key';

interface FakePlanItem {
  id: number;
  title: string;
  latitude: number | null;
  longitude: number | null;
  location: string | null;
  startTime: string | null;
  sortOrder: number;
}

describe('PlanRouteService', () => {
  let service: PlanRouteService;
  let prisma: any;
  let config: Pick<ConfigService, 'get'>;
  let fetchSpy: jest.SpyInstance;

  const buildService = (apiKey: string = API_KEY) => {
    prisma = {
      tripMember: { findUnique: jest.fn() },
      tripPlanItem: { findMany: jest.fn() },
      planRouteCache: { findUnique: jest.fn(), create: jest.fn() },
    };
    config = {
      get: jest.fn((key: string) =>
        key === 'GOOGLE_ROUTES_API_KEY' ? apiKey : undefined,
      ) as any,
    };
    service = new PlanRouteService(
      prisma as PrismaService,
      config as ConfigService,
    );
  };

  const asAcceptedMember = () => {
    prisma.tripMember.findUnique.mockResolvedValue({
      inviteStatus: InviteStatus.ACCEPTED,
    });
  };

  const mockItems = (items: FakePlanItem[]) => {
    prisma.tripPlanItem.findMany.mockResolvedValue(items);
  };

  const mockRoutesApiSuccess = () => {
    fetchSpy.mockImplementation(async (_url: string, init: any) => {
      const body = JSON.parse(init.body as string);
      const chunkSize = body.intermediates.length + 2;
      const legs = Array.from({ length: chunkSize - 1 }, (_, i) => ({
        polyline: { encodedPolyline: `enc${i}` },
        duration: '600s',
        distanceMeters: 5000,
      }));
      return {
        ok: true,
        status: 200,
        json: async () => ({ routes: [{ legs }] }),
      } as unknown as Response;
    });
  };

  beforeEach(() => {
    fetchSpy = jest.spyOn(globalThis, 'fetch').mockImplementation(() => {
      throw new Error(
        'unexpected fetch call — test should have mocked this explicitly',
      );
    });
    buildService();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('throws 403 for a non-member', async () => {
    prisma = {
      tripMember: { findUnique: jest.fn().mockResolvedValue(null) },
      tripPlanItem: { findMany: jest.fn() },
      planRouteCache: { findUnique: jest.fn(), create: jest.fn() },
    };
    service = new PlanRouteService(
      prisma as PrismaService,
      config as ConfigService,
    );

    await expect(service.getPlanRoute(1, 1, DATE)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(prisma.tripPlanItem.findMany).not.toHaveBeenCalled();
  });

  describe('pin ordering', () => {
    it('orders timed items before untimed, by startTime, then sortOrder, then id', async () => {
      asAcceptedMember();
      mockItems([
        {
          id: 3,
          title: 'Untimed B',
          latitude: 10,
          longitude: 20,
          location: null,
          startTime: null,
          sortOrder: 1,
        },
        {
          id: 2,
          title: 'Untimed A',
          latitude: 10,
          longitude: 20,
          location: null,
          startTime: null,
          sortOrder: 0,
        },
        {
          id: 1,
          title: 'Afternoon',
          latitude: 10,
          longitude: 20,
          location: 'Cafe',
          startTime: '14:00',
          sortOrder: 0,
        },
        {
          id: 5,
          title: 'Morning tie B',
          latitude: 10,
          longitude: 20,
          location: null,
          startTime: '09:00',
          sortOrder: 0,
        },
        {
          id: 4,
          title: 'Morning tie A',
          latitude: 10,
          longitude: 20,
          location: null,
          startTime: '09:00',
          sortOrder: 0,
        },
      ]);

      const result = await service.getPlanRoute(1, 1, DATE);

      expect(result.pins.map((p) => p.id)).toEqual([4, 5, 1, 2, 3]);
      expect(result.pins.map((p) => p.index)).toEqual([1, 2, 3, 4, 5]);
    });

    it('filters out items without coordinates without consuming an index', async () => {
      asAcceptedMember();
      mockItems([
        {
          id: 1,
          title: 'Located',
          latitude: 10,
          longitude: 20,
          location: null,
          startTime: '09:00',
          sortOrder: 0,
        },
        {
          id: 2,
          title: 'No coords',
          latitude: null,
          longitude: null,
          location: null,
          startTime: '08:00',
          sortOrder: 0,
        },
        {
          id: 3,
          title: 'Also located',
          latitude: 11,
          longitude: 21,
          location: null,
          startTime: '10:00',
          sortOrder: 0,
        },
      ]);

      const result = await service.getPlanRoute(1, 1, DATE);

      expect(result.pins.map((p) => p.id)).toEqual([1, 3]);
      expect(result.pins.map((p) => p.index)).toEqual([1, 2]);
    });
  });

  it('returns legs: [] and makes zero upstream calls for < 2 pins', async () => {
    asAcceptedMember();
    mockItems([
      {
        id: 1,
        title: 'Only stop',
        latitude: 10,
        longitude: 20,
        location: null,
        startTime: null,
        sortOrder: 0,
      },
    ]);

    const result = await service.getPlanRoute(1, 1, DATE);

    expect(result.legs).toEqual([]);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('falls back to null legs with no 500 when GOOGLE_ROUTES_API_KEY is unset', async () => {
    buildService('');
    asAcceptedMember();
    mockItems([
      {
        id: 1,
        title: 'A',
        latitude: 10,
        longitude: 20,
        location: null,
        startTime: null,
        sortOrder: 0,
      },
      {
        id: 2,
        title: 'B',
        latitude: 11,
        longitude: 21,
        location: null,
        startTime: null,
        sortOrder: 1,
      },
    ]);

    const result = await service.getPlanRoute(1, 1, DATE);

    expect(result.legs).toEqual([
      { polyline: null, durationSec: null, distanceM: null },
    ]);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  describe('caching', () => {
    const twoPins: FakePlanItem[] = [
      {
        id: 1,
        title: 'A',
        latitude: 10,
        longitude: 20,
        location: null,
        startTime: null,
        sortOrder: 0,
      },
      {
        id: 2,
        title: 'B',
        latitude: 11,
        longitude: 21,
        location: null,
        startTime: null,
        sortOrder: 1,
      },
    ];

    it('cache miss calls upstream once and inserts a row', async () => {
      asAcceptedMember();
      mockItems(twoPins);
      prisma.planRouteCache.findUnique.mockResolvedValue(null);
      mockRoutesApiSuccess();

      const result = await service.getPlanRoute(1, 1, DATE);

      expect(fetchSpy).toHaveBeenCalledTimes(1);
      expect(prisma.planRouteCache.create).toHaveBeenCalledTimes(1);
      expect(result.legs).toHaveLength(1);
      expect(result.legs[0].polyline).toBe('enc0');
    });

    it('cache hit makes zero upstream calls', async () => {
      asAcceptedMember();
      mockItems(twoPins);
      prisma.planRouteCache.findUnique.mockResolvedValue({
        payload: [{ polyline: 'cached', durationSec: 42, distanceM: 100 }],
      });

      const result = await service.getPlanRoute(1, 1, DATE);

      expect(fetchSpy).not.toHaveBeenCalled();
      expect(prisma.planRouteCache.create).not.toHaveBeenCalled();
      expect(result.legs).toEqual([
        { polyline: 'cached', durationSec: 42, distanceM: 100 },
      ]);
    });

    it('renaming a pin (same coordinates) reuses the same cache key', async () => {
      asAcceptedMember();
      prisma.planRouteCache.findUnique.mockResolvedValue(null);
      mockRoutesApiSuccess();

      mockItems(twoPins);
      await service.getPlanRoute(1, 1, DATE);
      const firstHash =
        prisma.planRouteCache.findUnique.mock.calls[0][0].where.routeHash;

      const renamed = twoPins.map((p) => ({
        ...p,
        title: `${p.title} renamed`,
      }));
      mockItems(renamed);
      await service.getPlanRoute(1, 1, DATE);
      const secondHash =
        prisma.planRouteCache.findUnique.mock.calls[1][0].where.routeHash;

      expect(secondHash).toBe(firstHash);
    });

    it('moving a pin changes the cache key (miss)', async () => {
      asAcceptedMember();
      prisma.planRouteCache.findUnique.mockResolvedValue(null);
      mockRoutesApiSuccess();

      mockItems(twoPins);
      await service.getPlanRoute(1, 1, DATE);
      const firstHash =
        prisma.planRouteCache.findUnique.mock.calls[0][0].where.routeHash;

      const moved = twoPins.map((p, i) =>
        i === 0 ? { ...p, latitude: p.latitude! + 1 } : p,
      );
      mockItems(moved);
      await service.getPlanRoute(1, 1, DATE);
      const secondHash =
        prisma.planRouteCache.findUnique.mock.calls[1][0].where.routeHash;

      expect(secondHash).not.toBe(firstHash);
    });
  });

  it('chunks > 12 pins with a one-pin overlap and stitches legs.length == pins.length - 1', async () => {
    asAcceptedMember();
    const pins: FakePlanItem[] = Array.from({ length: 14 }, (_, i) => ({
      id: i + 1,
      title: `Stop ${i + 1}`,
      latitude: 10 + i,
      longitude: 20 + i,
      location: null,
      startTime: null,
      sortOrder: i,
    }));
    mockItems(pins);
    prisma.planRouteCache.findUnique.mockResolvedValue(null);
    mockRoutesApiSuccess();

    const result = await service.getPlanRoute(1, 1, DATE);

    expect(fetchSpy).toHaveBeenCalledTimes(2);
    expect(result.legs).toHaveLength(13);
  });

  it('does not set routingPreference on the Routes API request', async () => {
    asAcceptedMember();
    mockItems([
      {
        id: 1,
        title: 'A',
        latitude: 10,
        longitude: 20,
        location: null,
        startTime: null,
        sortOrder: 0,
      },
      {
        id: 2,
        title: 'B',
        latitude: 11,
        longitude: 21,
        location: null,
        startTime: null,
        sortOrder: 1,
      },
    ]);
    prisma.planRouteCache.findUnique.mockResolvedValue(null);
    mockRoutesApiSuccess();

    await service.getPlanRoute(1, 1, DATE);

    const [, init] = fetchSpy.mock.calls[0];
    const body = JSON.parse(init.body as string);
    expect(body.routingPreference).toBeUndefined();
  });

  it('upstream failure returns null legs, pins still populated, and caches nothing', async () => {
    asAcceptedMember();
    mockItems([
      {
        id: 1,
        title: 'A',
        latitude: 10,
        longitude: 20,
        location: null,
        startTime: null,
        sortOrder: 0,
      },
      {
        id: 2,
        title: 'B',
        latitude: 11,
        longitude: 21,
        location: null,
        startTime: null,
        sortOrder: 1,
      },
    ]);
    prisma.planRouteCache.findUnique.mockResolvedValue(null);
    fetchSpy.mockImplementation(async () => {
      throw new Error('network down');
    });

    const result = await service.getPlanRoute(1, 1, DATE);

    expect(result.pins).toHaveLength(2);
    expect(result.legs).toEqual([
      { polyline: null, durationSec: null, distanceM: null },
    ]);
    expect(prisma.planRouteCache.create).not.toHaveBeenCalled();
  });
});
