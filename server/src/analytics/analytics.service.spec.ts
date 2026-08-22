import { Prisma } from '@prisma/client';
import { ClsService } from 'nestjs-cls';
import { PrismaService } from '../prisma/prisma.service';
import { AnalyticsService } from './analytics.service';
import { ANALYTICS_EVENTS } from './constants/events';

describe('AnalyticsService', () => {
  let service: AnalyticsService;
  let prisma: {
    analyticsEvent: {
      create: jest.Mock;
      createMany: jest.Mock;
    };
    analyticsSession: {
      upsert: jest.Mock;
      update: jest.Mock;
      updateMany: jest.Mock;
      create: jest.Mock;
      findUnique: jest.Mock;
    };
  };
  let cls: { get: jest.Mock };

  beforeEach(() => {
    prisma = {
      analyticsEvent: {
        create: jest.fn().mockResolvedValue({}),
        createMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      analyticsSession: {
        upsert: jest.fn().mockResolvedValue({}),
        update: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        create: jest.fn().mockResolvedValue({}),
        findUnique: jest.fn().mockResolvedValue(null),
      },
    };
    cls = { get: jest.fn() };

    service = new AnalyticsService(
      prisma as unknown as PrismaService,
      cls as unknown as ClsService,
    );
  });

  describe('track', () => {
    it('writes a row with userId, properties, and explicit sessionId', async () => {
      prisma.analyticsSession.findUnique.mockResolvedValue({ id: 'sess-1' });
      await service.track(ANALYTICS_EVENTS.TRIP_CREATED, {
        userId: 42,
        sessionId: 'sess-1',
        properties: { tripId: 7 },
      });

      expect(prisma.analyticsEvent.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          eventName: 'TRIP_CREATED',
          userId: 42,
          sessionId: 'sess-1',
          properties: { tripId: 7 },
        }),
      });
    });

    it('falls back to CLS-stored sessionId when not passed explicitly', async () => {
      cls.get.mockReturnValue('cls-sess');
      prisma.analyticsSession.findUnique.mockResolvedValue({ id: 'cls-sess' });

      await service.track(ANALYTICS_EVENTS.APP_OPEN, { userId: 1 });

      expect(prisma.analyticsEvent.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ sessionId: 'cls-sess' }),
      });
    });

    it('materializes a stub session when it does not exist yet, so the event keeps its sessionId', async () => {
      // Regression: events that raced ahead of POST /analytics/sessions (or
      // whose client registration was dropped on a pre-auth 401) used to be
      // written with sessionId=null, permanently orphaning the session.
      prisma.analyticsSession.findUnique.mockResolvedValue(null);

      await service.track(ANALYTICS_EVENTS.APP_OPEN, {
        userId: 1,
        sessionId: 'sess-unregistered',
      });

      expect(prisma.analyticsSession.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          id: 'sess-unregistered',
          userId: 1,
          platform: 'unknown',
        }),
      });
      expect(prisma.analyticsEvent.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ sessionId: 'sess-unregistered' }),
      });
    });

    it('keeps the sessionId when a concurrent request wins the create race (P2002)', async () => {
      // Regression: under concurrency several events for a brand-new session all
      // miss findUnique then collide on the insert. The loser must treat the
      // P2002 as success (the row exists now) and keep its session reference,
      // not orphan the event with sessionId=null.
      prisma.analyticsSession.findUnique.mockResolvedValue(null);
      prisma.analyticsSession.create.mockRejectedValue(
        new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
          code: 'P2002',
          clientVersion: '6.15.0',
        }),
      );

      await service.track(ANALYTICS_EVENTS.APP_OPEN, {
        userId: 1,
        sessionId: 'sess-raced',
      });

      expect(prisma.analyticsEvent.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ sessionId: 'sess-raced' }),
      });
    });

    it('writes sessionId=null when no session id is present at all', async () => {
      cls.get.mockReturnValue(undefined);

      await service.track(ANALYTICS_EVENTS.APP_OPEN, { userId: 1 });

      expect(prisma.analyticsSession.upsert).not.toHaveBeenCalled();
      expect(prisma.analyticsEvent.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ sessionId: null }),
      });
    });

    it('falls back to sessionId=null if materializing the stub fails', async () => {
      prisma.analyticsSession.findUnique.mockResolvedValue(null);
      prisma.analyticsSession.create.mockRejectedValue(new Error('db down'));

      await service.track(ANALYTICS_EVENTS.APP_OPEN, {
        userId: 1,
        sessionId: 'sess-x',
      });

      expect(prisma.analyticsEvent.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ sessionId: null }),
      });
    });

    it('swallows DB errors (never throws)', async () => {
      prisma.analyticsEvent.create.mockRejectedValue(new Error('boom'));
      await expect(
        service.track(ANALYTICS_EVENTS.APP_OPEN, { userId: 1 }),
      ).resolves.toBeUndefined();
    });
  });

  describe('startSession', () => {
    it('upserts a session row', async () => {
      await service.startSession(
        {
          id: '11111111-1111-1111-1111-111111111111',
          platform: 'ios',
          appVersion: '1.0.0',
          osVersion: '17.5',
          startedAt: '2026-05-05T00:00:00.000Z',
        },
        42,
      );

      expect(prisma.analyticsSession.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: '11111111-1111-1111-1111-111111111111' },
          create: expect.objectContaining({
            id: '11111111-1111-1111-1111-111111111111',
            userId: 42,
            platform: 'ios',
          }),
        }),
      );
    });

    it('backfills authoritative metadata on the update branch (corrects a lazily-materialized stub)', async () => {
      await service.startSession(
        {
          id: '11111111-1111-1111-1111-111111111111',
          platform: 'ios',
          appVersion: '1.2.3',
          osVersion: '18.0',
          startedAt: '2026-05-17T00:00:00.000Z',
        },
        7,
      );

      expect(prisma.analyticsSession.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          update: expect.objectContaining({
            userId: 7,
            platform: 'ios',
            appVersion: '1.2.3',
            osVersion: '18.0',
            startedAt: new Date('2026-05-17T00:00:00.000Z'),
          }),
        }),
      );
    });

    it('swallows DB errors', async () => {
      prisma.analyticsSession.upsert.mockRejectedValue(new Error('db down'));
      await expect(
        service.startSession(
          {
            id: '11111111-1111-1111-1111-111111111111',
            platform: 'ios',
            startedAt: '2026-05-05T00:00:00.000Z',
          },
          1,
        ),
      ).resolves.toBeUndefined();
    });

    it('applies authoritative metadata via update when a concurrent create wins the race (P2002)', async () => {
      prisma.analyticsSession.upsert.mockRejectedValue(
        new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
          code: 'P2002',
          clientVersion: '6.15.0',
        }),
      );

      await service.startSession(
        {
          id: '11111111-1111-1111-1111-111111111111',
          platform: 'ios',
          appVersion: '1.2.3',
          osVersion: '18.0',
          startedAt: '2026-05-17T00:00:00.000Z',
        },
        7,
      );

      expect(prisma.analyticsSession.update).toHaveBeenCalledWith({
        where: { id: '11111111-1111-1111-1111-111111111111' },
        data: expect.objectContaining({
          userId: 7,
          platform: 'ios',
          appVersion: '1.2.3',
          osVersion: '18.0',
          startedAt: new Date('2026-05-17T00:00:00.000Z'),
        }),
      });
    });
  });

  describe('endSession', () => {
    it('updates the endedAt timestamp', async () => {
      const ts = new Date('2026-05-05T01:00:00.000Z');
      await service.endSession('sess-1', ts);
      expect(prisma.analyticsSession.updateMany).toHaveBeenCalledWith({
        where: { id: 'sess-1' },
        data: { endedAt: ts },
      });
    });
  });

  describe('recordClientEvents', () => {
    it('drops server-emitted events from a mixed batch', async () => {
      prisma.analyticsSession.findUnique.mockResolvedValue({ id: 'sess-1' });
      await service.recordClientEvents(
        [
          {
            eventName: ANALYTICS_EVENTS.APP_OPEN,
            occurredAt: '2026-05-05T00:00:00.000Z',
          },
          {
            // Server-emitted, must not be persisted via this path.
            eventName: ANALYTICS_EVENTS.TRIP_CREATED,
            occurredAt: '2026-05-05T00:00:01.000Z',
          },
          {
            eventName: ANALYTICS_EVENTS.MARKET_OPENED,
            occurredAt: '2026-05-05T00:00:02.000Z',
          },
        ],
        { userId: 7, sessionId: 'sess-1' },
      );

      expect(prisma.analyticsEvent.createMany).toHaveBeenCalledTimes(1);
      const call = prisma.analyticsEvent.createMany.mock.calls[0][0];
      expect(call.data).toHaveLength(2);
      expect(call.data.map((e: { eventName: string }) => e.eventName)).toEqual([
        'APP_OPEN',
        'MARKET_OPENED',
      ]);
    });

    it('skips the DB call when no client events remain after filtering', async () => {
      await service.recordClientEvents(
        [
          {
            eventName: ANALYTICS_EVENTS.TRIP_CREATED,
            occurredAt: '2026-05-05T00:00:00.000Z',
          },
        ],
        { userId: 7, sessionId: null },
      );
      expect(prisma.analyticsEvent.createMany).not.toHaveBeenCalled();
    });
  });
});
