import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { InviteStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { TripActivityService } from '../trip-activity/trip-activity.service';
import { PlanItemsService } from './plan-items.service';

describe('PlanItemsService', () => {
  let service: PlanItemsService;
  let prisma: any;
  let activityService: Pick<TripActivityService, 'log'>;
  let storageService: Pick<StorageService, 'deleteObject'>;

  beforeEach(() => {
    prisma = {
      tripMember: {
        findUnique: jest.fn(),
        findMany: jest.fn().mockResolvedValue([]),
      },
      marketplaceAcquisition: {
        findUnique: jest.fn(),
      },
      trip: {
        findUnique: jest.fn().mockResolvedValue({ marketplaceListingId: null }),
        updateMany: jest.fn(),
      },
      tripPlanItem: {
        findMany: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
        findUnique: jest.fn(),
        findUniqueOrThrow: jest.fn(),
      },
      tripPlanItemMember: {
        createMany: jest.fn(),
      },
      $transaction: jest.fn((fn) => fn(prisma)),
    };

    activityService = { log: jest.fn() };
    storageService = { deleteObject: jest.fn() };

    service = new PlanItemsService(
      prisma as PrismaService,
      activityService as TripActivityService,
      storageService as StorageService,
      { track: jest.fn() } as any,
    );
  });

  describe('applyAcquisitionToTrip', () => {
    const tripId = 10;
    const acquisitionId = 20;
    const userId = 1;

    beforeEach(() => {
      prisma.tripMember.findUnique.mockResolvedValue({
        tripId,
        userId,
        inviteStatus: InviteStatus.ACCEPTED,
      });
    });

    it('throws ForbiddenException if user is not a trip member', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(null);

      await expect(
        service.applyAcquisitionToTrip(tripId, acquisitionId, userId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws NotFoundException if acquisition is missing', async () => {
      prisma.marketplaceAcquisition.findUnique.mockResolvedValue(null);

      await expect(
        service.applyAcquisitionToTrip(tripId, acquisitionId, userId),
      ).rejects.toThrow(NotFoundException);
    });

    it('throws NotFoundException if acquisition belongs to another user', async () => {
      prisma.marketplaceAcquisition.findUnique.mockResolvedValue({
        id: acquisitionId,
        userId: 999,
        listingId: 5,
        items: [{ id: 1 }],
      });

      await expect(
        service.applyAcquisitionToTrip(tripId, acquisitionId, userId),
      ).rejects.toThrow(NotFoundException);
    });

    it('throws NotFoundException if acquired plan has no items', async () => {
      prisma.marketplaceAcquisition.findUnique.mockResolvedValue({
        id: acquisitionId,
        userId,
        listingId: 5,
        items: [],
      });

      await expect(
        service.applyAcquisitionToTrip(tripId, acquisitionId, userId),
      ).rejects.toThrow(NotFoundException);
    });

    it('throws ConflictException if plan is already applied to this trip', async () => {
      prisma.marketplaceAcquisition.findUnique.mockResolvedValue({
        id: acquisitionId,
        userId,
        listingId: 5,
        items: [{ id: 1, dayNumber: 1, sortOrder: 0 }],
      });
      prisma.trip.findUnique.mockResolvedValue({ marketplaceListingId: 5 });

      await expect(
        service.applyAcquisitionToTrip(tripId, acquisitionId, userId),
      ).rejects.toThrow(ConflictException);
    });

    it('copies acquired items into trip plan items and tags trip with listingId', async () => {
      prisma.marketplaceAcquisition.findUnique.mockResolvedValue({
        id: acquisitionId,
        userId,
        listingId: 5,
        items: [
          {
            id: 100,
            dayNumber: 1,
            title: 'Visit Temple',
            description: 'Morning visit',
            location: 'Old Quarter',
            startTime: '09:00',
            category: 'TICKET',
            imageUrls: [],
            sortOrder: 0,
          },
          {
            id: 101,
            dayNumber: 1,
            title: 'Lunch',
            description: null,
            location: 'Pho Street',
            startTime: '12:00',
            category: 'FOOD',
            imageUrls: [],
            sortOrder: 1,
          },
        ],
      });

      prisma.tripMember.findMany.mockResolvedValue([
        { userId: 1 },
        { userId: 2 },
      ]);

      let seq = 0;
      prisma.tripPlanItem.create.mockImplementation(() => {
        seq++;
        return Promise.resolve({ id: 200 + seq });
      });

      const now = new Date();
      prisma.tripPlanItem.findMany.mockResolvedValue([
        {
          id: 201,
          tripId,
          planDate: null,
          dayNumber: 1,
          title: 'Visit Temple',
          description: 'Morning visit',
          location: 'Old Quarter',
          startTime: '09:00',
          category: 'TICKET',
          voiceUrl: null,
          voiceDuration: null,
          sortOrder: 0,
          createdAt: now,
          members: [],
        },
      ]);

      await service.applyAcquisitionToTrip(tripId, acquisitionId, userId);

      expect(prisma.trip.updateMany).toHaveBeenCalledWith({
        where: { id: tripId, marketplaceListingId: null },
        data: { marketplaceListingId: 5 },
      });
      expect(prisma.tripPlanItem.create).toHaveBeenCalledTimes(2);
      expect(prisma.tripPlanItem.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          tripId,
          title: 'Visit Temple',
          dayNumber: 1,
        }),
      });
      expect(activityService.log).toHaveBeenCalledWith(
        tripId,
        userId,
        'PLAN_ITEM_CREATED',
        201,
        { title: `Applied acquired plan #${acquisitionId}` },
      );
    });

    it('skips trip.updateMany when acquisition listingId is null (listing was deleted)', async () => {
      prisma.marketplaceAcquisition.findUnique.mockResolvedValue({
        id: acquisitionId,
        userId,
        listingId: null,
        items: [
          {
            id: 100,
            dayNumber: 1,
            title: 'Orphaned snapshot',
            description: null,
            location: null,
            startTime: null,
            category: null,
            imageUrls: [],
            sortOrder: 0,
          },
        ],
      });

      prisma.tripPlanItem.create.mockResolvedValue({ id: 500 });
      prisma.tripPlanItem.findMany.mockResolvedValue([]);

      await service.applyAcquisitionToTrip(tripId, acquisitionId, userId);

      expect(prisma.trip.updateMany).not.toHaveBeenCalled();
    });
  });

  describe('updatePlanItem', () => {
    const tripId = 10;
    const itemId = 42;
    const userId = 1;

    beforeEach(() => {
      prisma.tripMember.findUnique.mockResolvedValue({
        tripId,
        userId,
        inviteStatus: InviteStatus.ACCEPTED,
      });
      prisma.tripPlanItem.findUnique.mockResolvedValue({
        id: itemId,
        title: 'Old title',
        tripId,
        voiceUrl: null,
      });
      prisma.tripPlanItem.update.mockResolvedValue({ id: itemId });
      prisma.tripPlanItem.findUniqueOrThrow.mockResolvedValue({
        id: itemId,
        tripId,
        planDate: null,
        dayNumber: 1,
        title: 'Old title',
        description: null,
        location: null,
        latitude: null,
        longitude: null,
        address: null,
        startTime: null,
        category: null,
        voiceUrl: null,
        voiceDuration: null,
        sortOrder: 0,
        createdAt: new Date(),
        members: [],
      });
    });

    it('clears the note when description is an empty string (stores null)', async () => {
      await service.updatePlanItem(tripId, itemId, userId, {
        description: '',
      } as any);

      expect(prisma.tripPlanItem.update).toHaveBeenCalledWith({
        where: { id: itemId },
        data: expect.objectContaining({ description: null }),
      });
    });

    it('leaves the note untouched when description is omitted', async () => {
      await service.updatePlanItem(tripId, itemId, userId, {
        title: 'New title',
      } as any);

      const call = prisma.tripPlanItem.update.mock.calls[0][0];
      expect(call.data).not.toHaveProperty('description');
    });
  });
});
