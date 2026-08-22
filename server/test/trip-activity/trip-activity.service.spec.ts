import { Logger } from '@nestjs/common';
import { ActivityAction } from '@prisma/client';
import { PrismaService } from '../../src/prisma/prisma.service';
import { TripActivityService } from '../../src/trip-activity/trip-activity.service';

describe('TripActivityService', () => {
  let service: TripActivityService;
  let prisma: Record<string, any>;

  beforeEach(() => {
    prisma = {
      tripActivity: {
        create: jest.fn(),
      },
    };

    service = new TripActivityService(prisma as unknown as PrismaService);
  });

  describe('log', () => {
    it('should create an activity record with correct data', async () => {
      prisma.tripActivity.create.mockResolvedValue({ id: 1 });

      await service.log(1, 5, ActivityAction.TRIP_CREATED, undefined, {
        name: 'Beach Trip',
      });

      expect(prisma.tripActivity.create).toHaveBeenCalledWith({
        data: {
          tripId: 1,
          userId: 5,
          action: ActivityAction.TRIP_CREATED,
          targetId: undefined,
          metadata: { name: 'Beach Trip' },
          createdAt: expect.any(Date),
        },
      });
    });

    it('should create an activity record with targetId', async () => {
      prisma.tripActivity.create.mockResolvedValue({ id: 2 });

      await service.log(1, 5, ActivityAction.MEMBER_INVITED, 10, {
        displayName: 'Alice',
      });

      expect(prisma.tripActivity.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          action: ActivityAction.MEMBER_INVITED,
          targetId: 10,
          metadata: { displayName: 'Alice' },
        }),
      });
    });

    it('should not throw when prisma create fails', async () => {
      prisma.tripActivity.create.mockRejectedValue(
        new Error('DB connection lost'),
      );
      const warnSpy = jest.spyOn(Logger.prototype, 'warn').mockImplementation();

      await expect(
        service.log(1, 5, ActivityAction.TRIP_CREATED),
      ).resolves.not.toThrow();

      expect(warnSpy).toHaveBeenCalledWith(
        expect.stringContaining('Failed to log activity TRIP_CREATED'),
      );

      warnSpy.mockRestore();
    });

    it('should work without optional parameters', async () => {
      prisma.tripActivity.create.mockResolvedValue({ id: 3 });

      await service.log(1, 5, ActivityAction.TRIP_UPDATED);

      expect(prisma.tripActivity.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          targetId: undefined,
          metadata: undefined,
        }),
      });
    });
  });
});
