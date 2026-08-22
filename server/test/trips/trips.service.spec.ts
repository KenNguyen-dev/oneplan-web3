import {
  BadRequestException,
  ForbiddenException,
  HttpException,
  NotFoundException,
} from '@nestjs/common';
import { Currency, InviteStatus, SubscriptionStatus } from '@prisma/client';
import { BudgetsService } from '../../src/budgets/budgets.service';
import { PlanItemsService } from '../../src/plan-items/plan-items.service';
import { PrismaService } from '../../src/prisma/prisma.service';
import { TripActivityService } from '../../src/trip-activity/trip-activity.service';
import { TripsService } from '../../src/trips/trips.service';

describe('TripsService', () => {
  let service: TripsService;
  let prisma: Record<string, any>;
  let activityService: Record<string, any>;
  let budgetsService: Record<string, any>;
  let planItemsService: Record<string, any>;
  let storageService: Record<string, any>;
  let tripsHandler: Record<string, any>;
  let notificationsService: Record<string, any>;

  const mockUser = {
    id: 1,
    email: 'test@example.com',
    displayName: 'Test User',
    avatarUrl: null,
  };

  const mockTrip = {
    id: 1,
    name: 'Trip to Dubai',
    coverImageUrl: null,
    status: 'PLANNING',
    startDate: new Date('2026-04-01'),
    endDate: new Date('2026-04-10'),
    inviteCode: 'abc123',
    createdById: 1,
    createdAt: new Date('2026-03-18'),
    cityId: null,
    stateId: null,
    countryId: null,
    currency: Currency.VND,
    localCurrencies: [] as Currency[],
    marketplaceListingId: null,
  };

  const mockTripWithIncludes = {
    ...mockTrip,
    city: null,
    state: null,
    country: null,
    members: [
      {
        id: 1,
        tripId: 1,
        userId: 1,
        inviteStatus: InviteStatus.ACCEPTED,
        joinedAt: new Date(),
        user: { id: 1, displayName: 'Test User', avatarUrl: null },
      },
    ],
  };

  const mockMember = {
    id: 1,
    tripId: 1,
    userId: 1,
    inviteStatus: InviteStatus.ACCEPTED,
    joinedAt: new Date(),
  };

  beforeEach(() => {
    prisma = {
      trip: {
        create: jest.fn(),
        findMany: jest.fn(),
        findFirst: jest.fn(),
        findUnique: jest.fn(),
        findUniqueOrThrow: jest.fn(),
        update: jest.fn(),
        delete: jest.fn(),
      },
      tripMember: {
        create: jest.fn(),
        createMany: jest.fn(),
        findUnique: jest.fn(),
        findMany: jest.fn(),
        update: jest.fn(),
        upsert: jest.fn(),
        delete: jest.fn(),
      },
      user: {
        findUnique: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      country: {
        findUnique: jest.fn(),
      },
      budget: {
        count: jest.fn().mockResolvedValue(0),
      },
      marketplaceRating: {
        findUnique: jest.fn().mockResolvedValue(null),
      },
      tripPlanItem: {
        findMany: jest.fn().mockResolvedValue([]),
        update: jest.fn(),
      },
      budgetPayment: {
        findMany: jest.fn().mockResolvedValue([]),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      expenseShare: {
        findMany: jest.fn().mockResolvedValue([]),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      expense: {
        findMany: jest.fn().mockResolvedValue([]),
        update: jest.fn(),
        count: jest.fn().mockResolvedValue(0),
      },
      $transaction: jest.fn((cb: (tx: any) => Promise<any>) => cb(prisma)),
    };

    activityService = {
      log: jest.fn(),
    };

    budgetsService = {
      addPaymentsForMember: jest.fn().mockResolvedValue(undefined),
    };

    planItemsService = {
      addMemberToAllPlanItems: jest.fn().mockResolvedValue(undefined),
    };

    storageService = {
      getSignedThumbUrl: jest.fn().mockImplementation(async (objectKey) => ({
        url: `https://signed.example/${objectKey}`,
      })),
    };

    tripsHandler = {
      sendTripInvite: jest.fn(),
      sendTripEnded: jest.fn(),
      sendTripDeleted: jest.fn(),
      getOnlineUserIds: jest.fn().mockReturnValue([]),
    };

    notificationsService = {
      sendMemberJoinedPush: jest.fn(),
      sendMemberLeftPush: jest.fn(),
      sendTripInvitePush: jest.fn(),
    };

    service = new TripsService(
      prisma as unknown as PrismaService,
      activityService as unknown as TripActivityService,
      storageService as any,
      budgetsService as unknown as BudgetsService,
      planItemsService as unknown as PlanItemsService,
      tripsHandler as any,
      notificationsService as any,
      { track: jest.fn() } as any,
      // A trip with no vault is always deletable, which is the default here.
      {
        assertDeletable: jest.fn().mockResolvedValue(undefined),
        syncMembers: jest.fn().mockResolvedValue(0),
        setMemberRole: jest.fn().mockResolvedValue(undefined),
      } as any,
      {
        memberNetMicro: jest.fn().mockResolvedValue(null),
        memberDepositMicro: jest.fn().mockResolvedValue(0n),
      } as any,
    );
  });

  describe('createTrip', () => {
    it('should create a trip and add creator as accepted member', async () => {
      prisma.trip.create.mockResolvedValue(mockTrip);
      prisma.tripMember.create.mockResolvedValue(mockMember);
      prisma.trip.findUniqueOrThrow.mockResolvedValue(mockTripWithIncludes);

      const result = await service.createTrip(1, {
        name: 'Trip to Dubai',
        startDate: '2026-04-01',
        endDate: '2026-04-10',
      });

      expect(prisma.$transaction).toHaveBeenCalled();
      expect(prisma.trip.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            name: 'Trip to Dubai',
            createdById: 1,
            inviteCode: expect.any(String),
          }),
        }),
      );
      expect(prisma.tripMember.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            tripId: 1,
            userId: 1,
            inviteStatus: InviteStatus.ACCEPTED,
          }),
        }),
      );
      expect(result.id).toBe(1);
      expect(result.name).toBe('Trip to Dubai');
      expect(result.members).toHaveLength(1);
    });

    it('auto-suggests localCurrencies from country when country currency differs from home', async () => {
      prisma.user.findUnique.mockResolvedValue({
        preferredCurrency: Currency.VND,
      });
      prisma.country.findUnique.mockResolvedValue({ currency: 'THB' });
      prisma.trip.create.mockResolvedValue(mockTrip);
      prisma.tripMember.create.mockResolvedValue(mockMember);
      prisma.trip.findUniqueOrThrow.mockResolvedValue({
        ...mockTripWithIncludes,
        localCurrencies: [Currency.THB],
      });

      const result = await service.createTrip(1, {
        name: 'Trip to Thailand',
        countryId: 42,
      } as any);

      expect(prisma.country.findUnique).toHaveBeenCalledWith({
        where: { id: 42 },
        select: { currency: true },
      });

      const createArgs = prisma.trip.create.mock.calls[0][0];
      expect(createArgs.data.localCurrencies).toEqual([Currency.THB]);
      expect(result.localCurrencies).toEqual([Currency.THB]);
    });

    it('leaves localCurrencies empty when country currency matches home currency', async () => {
      prisma.user.findUnique.mockResolvedValue({
        preferredCurrency: Currency.VND,
      });
      prisma.country.findUnique.mockResolvedValue({ currency: 'VND' });
      prisma.trip.create.mockResolvedValue(mockTrip);
      prisma.tripMember.create.mockResolvedValue(mockMember);
      prisma.trip.findUniqueOrThrow.mockResolvedValue(mockTripWithIncludes);

      await service.createTrip(1, {
        name: 'Trip to Vietnam',
        countryId: 100,
      } as any);

      const createArgs = prisma.trip.create.mock.calls[0][0];
      expect(createArgs.data.localCurrencies).toEqual([]);
    });

    it('respects explicit empty localCurrencies (no auto-suggest)', async () => {
      prisma.user.findUnique.mockResolvedValue({
        preferredCurrency: Currency.VND,
      });
      prisma.trip.create.mockResolvedValue(mockTrip);
      prisma.tripMember.create.mockResolvedValue(mockMember);
      prisma.trip.findUniqueOrThrow.mockResolvedValue(mockTripWithIncludes);

      await service.createTrip(1, {
        name: 'Trip to Thailand',
        countryId: 42,
        localCurrencies: [],
      } as any);

      expect(prisma.country.findUnique).not.toHaveBeenCalled();
      const createArgs = prisma.trip.create.mock.calls[0][0];
      expect(createArgs.data.localCurrencies).toEqual([]);
    });
  });

  describe('listMyTrips', () => {
    it('should return trips where user is an accepted member', async () => {
      prisma.trip.findMany.mockResolvedValue([
        {
          ...mockTrip,
          city: null,
          state: null,
          country: null,
          members: [],
          _count: { members: 3 },
        },
      ]);

      const result = await service.listMyTrips(1);

      expect(prisma.trip.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            members: {
              some: { userId: 1, inviteStatus: InviteStatus.ACCEPTED },
            },
          },
        }),
      );
      expect(result).toHaveLength(1);
      expect(result[0].memberCount).toBe(3);
    });

    it('should filter by status when provided', async () => {
      prisma.trip.findMany.mockResolvedValue([]);

      await service.listMyTrips(1, 'PLANNING' as any);

      expect(prisma.trip.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            status: 'PLANNING',
          }),
        }),
      );
    });

    it('should return empty array when user has no trips', async () => {
      prisma.trip.findMany.mockResolvedValue([]);

      const result = await service.listMyTrips(1);

      expect(result).toEqual([]);
    });
  });

  describe('getTrip', () => {
    it('should return trip detail when user is a member', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUniqueOrThrow.mockResolvedValue(mockTripWithIncludes);

      const result = await service.getTrip(1, 1);

      expect(result.id).toBe(1);
      expect(result.members).toHaveLength(1);
    });

    it('should throw ForbiddenException when user is not a member', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(null);

      await expect(service.getTrip(1, 99)).rejects.toThrow(ForbiddenException);
    });

    it('should throw ForbiddenException when invite is pending', async () => {
      prisma.tripMember.findUnique.mockResolvedValue({
        ...mockMember,
        inviteStatus: InviteStatus.PENDING,
      });

      await expect(service.getTrip(1, 1)).rejects.toThrow(ForbiddenException);
    });
  });

  describe('updateTrip', () => {
    it('should update trip when user is a member', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.update.mockResolvedValue(mockTrip);
      prisma.trip.findUniqueOrThrow.mockResolvedValue(mockTripWithIncludes);

      const result = await service.updateTrip(1, 1, { name: 'Updated Name' });

      expect(prisma.trip.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 1 },
          data: expect.objectContaining({ name: 'Updated Name' }),
        }),
      );
      expect(result.id).toBe(1);
    });

    it('should throw ForbiddenException when non-member tries to update', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(null);

      await expect(
        service.updateTrip(1, 99, { name: 'Hacked' }),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should allow creator to start trip when no other ongoing trip exists', async () => {
      const ongoingTrip = {
        ...mockTrip,
        status: 'ONGOING',
      };
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUnique.mockResolvedValue({ createdById: 1 });
      prisma.tripMember.findMany.mockResolvedValue([
        { userId: 1, user: { displayName: 'Test User' } },
      ]);
      prisma.trip.findMany.mockResolvedValue([]);
      prisma.trip.update.mockResolvedValue(ongoingTrip);
      prisma.trip.findUniqueOrThrow.mockResolvedValue({
        ...mockTripWithIncludes,
        status: 'ONGOING',
      });

      const result = await service.updateTrip(1, 1, {
        status: 'ONGOING' as any,
      });

      expect(prisma.tripMember.findMany).toHaveBeenCalled();
      expect(prisma.trip.findMany).toHaveBeenCalled();
      expect(prisma.trip.update).toHaveBeenCalled();
      expect(result.status).toBe('ONGOING');
    });

    it('should throw ForbiddenException when non-creator tries to start trip', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUnique.mockResolvedValue({ createdById: 2 });

      await expect(
        service.updateTrip(1, 1, { status: 'ONGOING' as any }),
      ).rejects.toThrow(ForbiddenException);

      expect(prisma.trip.update).not.toHaveBeenCalled();
    });

    it('should throw HttpException with MEMBER_CONFLICT when a member has an ongoing trip', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUnique.mockResolvedValue({ createdById: 1 });
      prisma.tripMember.findMany.mockResolvedValue([
        { userId: 1, user: { displayName: 'Test User' } },
        { userId: 2, user: { displayName: 'Other User' } },
      ]);
      prisma.trip.findMany.mockResolvedValue([
        {
          members: [{ user: { displayName: 'Other User' } }],
        },
      ]);

      await expect(
        service.updateTrip(1, 1, { status: 'ONGOING' as any }),
      ).rejects.toThrow(HttpException);

      try {
        await service.updateTrip(1, 1, { status: 'ONGOING' as any });
      } catch (e) {
        expect(e).toBeInstanceOf(HttpException);
        const response = (e as HttpException).getResponse();
        expect(response).toEqual(
          expect.objectContaining({
            error: 'MEMBER_CONFLICT',
            memberNames: ['Other User'],
          }),
        );
      }

      expect(prisma.trip.update).not.toHaveBeenCalled();
    });

    it('should preserve existing startDate when starting trip', async () => {
      const existingStartDate = new Date('2026-04-10');
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUnique
        .mockResolvedValueOnce({ createdById: 1 })
        .mockResolvedValueOnce({ startDate: existingStartDate });
      prisma.tripMember.findMany.mockResolvedValue([
        { userId: 1, user: { displayName: 'Test User' } },
      ]);
      prisma.trip.findMany.mockResolvedValue([]);
      prisma.trip.update.mockResolvedValue({
        ...mockTrip,
        status: 'ONGOING',
      });
      prisma.trip.findUniqueOrThrow.mockResolvedValue({
        ...mockTripWithIncludes,
        status: 'ONGOING',
      });

      await service.updateTrip(1, 1, { status: 'ONGOING' as any });

      const updateCall = prisma.trip.update.mock.calls[0][0];
      expect(updateCall.data).not.toHaveProperty('startDate');
    });

    it('allows editing localCurrencies even when budgets/expenses exist', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUnique.mockResolvedValue({ startDate: null });
      prisma.budget.count.mockResolvedValue(3);
      prisma.expense.count.mockResolvedValue(5);
      prisma.trip.update.mockResolvedValue(mockTrip);
      prisma.trip.findUniqueOrThrow.mockResolvedValue({
        ...mockTripWithIncludes,
        localCurrencies: [Currency.THB],
      });

      const result = await service.updateTrip(1, 1, {
        localCurrencies: [Currency.THB],
      } as any);

      const updateArgs = prisma.trip.update.mock.calls[0][0];
      expect(updateArgs.data.localCurrencies).toEqual([Currency.THB]);
      expect(result.localCurrencies).toEqual([Currency.THB]);
    });

    it('still blocks currency change when budgets or expenses exist', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUniqueOrThrow.mockResolvedValue({
        currency: Currency.VND,
      });
      prisma.budget.count.mockResolvedValue(1);
      prisma.expense.count.mockResolvedValue(0);

      await expect(
        service.updateTrip(1, 1, { currency: Currency.THB } as any),
      ).rejects.toThrow(BadRequestException);

      expect(prisma.trip.update).not.toHaveBeenCalled();
    });

    it('should auto-set startDate when starting trip without one', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUnique
        .mockResolvedValueOnce({ createdById: 1 })
        .mockResolvedValueOnce({ startDate: null });
      prisma.tripMember.findMany.mockResolvedValue([
        { userId: 1, user: { displayName: 'Test User' } },
      ]);
      prisma.trip.findMany.mockResolvedValue([]);
      prisma.trip.update.mockResolvedValue({
        ...mockTrip,
        status: 'ONGOING',
      });
      prisma.trip.findUniqueOrThrow.mockResolvedValue({
        ...mockTripWithIncludes,
        status: 'ONGOING',
      });

      await service.updateTrip(1, 1, { status: 'ONGOING' as any });

      const updateCall = prisma.trip.update.mock.calls[0][0];
      expect(updateCall.data).toHaveProperty('startDate');
      expect(updateCall.data.startDate).toBeInstanceOf(Date);
    });

    it('broadcasts realtime when ending trip', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUnique.mockResolvedValue({ startDate: null });
      prisma.trip.update.mockResolvedValue({
        ...mockTrip,
        status: 'ENDED',
      });
      prisma.trip.findUniqueOrThrow.mockResolvedValue({
        ...mockTripWithIncludes,
        status: 'ENDED',
      });

      await service.updateTrip(1, 1, { status: 'ENDED' as any });

      expect(tripsHandler.sendTripEnded).toHaveBeenCalledWith(1);
    });

    it('does not broadcast trip ended for non-ended updates', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUnique.mockResolvedValue({ startDate: null });
      prisma.trip.update.mockResolvedValue(mockTrip);
      prisma.trip.findUniqueOrThrow.mockResolvedValue(mockTripWithIncludes);

      await service.updateTrip(1, 1, { name: 'Updated Name' });

      expect(tripsHandler.sendTripEnded).not.toHaveBeenCalled();
    });
  });

  describe('deleteTrip', () => {
    it('should delete trip when user is the creator', async () => {
      prisma.trip.findUnique.mockResolvedValue({ createdById: 1 });
      prisma.trip.delete.mockResolvedValue(mockTrip);

      await service.deleteTrip(1, 1);

      expect(prisma.trip.delete).toHaveBeenCalledWith({ where: { id: 1 } });
    });

    it('should throw ForbiddenException when non-creator tries to delete', async () => {
      prisma.trip.findUnique.mockResolvedValue({ createdById: 1 });

      await expect(service.deleteTrip(1, 99)).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('should throw NotFoundException when trip does not exist', async () => {
      prisma.trip.findUnique.mockResolvedValue(null);

      await expect(service.deleteTrip(999, 1)).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('inviteMembers', () => {
    it('should invite members when user is a trip member', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember);
      prisma.trip.findUnique.mockResolvedValue({
        inviteCode: 'abc123',
        name: 'Trip to Dubai',
        coverImageUrl: null,
      });
      prisma.user.findUnique.mockResolvedValue({ displayName: 'Inviter' });
      prisma.tripMember.createMany.mockResolvedValue({ count: 2 });
      prisma.tripMember.findMany.mockResolvedValue([
        {
          id: 2,
          tripId: 1,
          userId: 10,
          inviteStatus: InviteStatus.PENDING,
          joinedAt: null,
          user: { id: 10, displayName: 'User 10', avatarUrl: null },
        },
        {
          id: 3,
          tripId: 1,
          userId: 11,
          inviteStatus: InviteStatus.PENDING,
          joinedAt: null,
          user: { id: 11, displayName: 'User 11', avatarUrl: null },
        },
      ]);

      const result = await service.inviteMembers(1, 1, {
        userIds: [10, 11],
      });

      expect(prisma.tripMember.createMany).toHaveBeenCalledWith(
        expect.objectContaining({
          skipDuplicates: true,
        }),
      );
      expect(result).toHaveLength(2);
      expect(result[0].inviteStatus).toBe(InviteStatus.PENDING);
    });

    it('should throw ForbiddenException when inviter is not a member', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(null);

      await expect(
        service.inviteMembers(1, 99, { userIds: [10] }),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  describe('joinTrip', () => {
    it('should join trip via invite code', async () => {
      prisma.trip.findUnique.mockResolvedValue(mockTrip);
      prisma.tripMember.upsert.mockResolvedValue(mockMember);
      prisma.user.findUnique.mockResolvedValue({ displayName: 'Test User' });
      prisma.trip.findUniqueOrThrow.mockResolvedValue(mockTripWithIncludes);

      const result = await service.joinTrip('abc123', 2);

      expect(prisma.trip.findUnique).toHaveBeenCalledWith({
        where: { inviteCode: 'abc123' },
      });
      expect(prisma.tripMember.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { tripId_userId: { tripId: 1, userId: 2 } },
          create: expect.objectContaining({
            inviteStatus: InviteStatus.ACCEPTED,
          }),
          update: expect.objectContaining({
            inviteStatus: InviteStatus.ACCEPTED,
          }),
        }),
      );
      expect(result.id).toBe(1);
    });

    it('should throw NotFoundException for invalid invite code', async () => {
      prisma.trip.findUnique.mockResolvedValue(null);

      await expect(service.joinTrip('invalid', 1)).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('getInvitePreview', () => {
    it('should return preview with signed cover URL and accepted member count', async () => {
      prisma.trip.findUnique.mockResolvedValue({
        name: 'Trip to Dubai',
        coverImageUrl: 'trip-covers/abc123',
        status: 'PLANNING',
        _count: { members: 4 },
      });

      const result = await service.getInvitePreview('abc123');

      expect(prisma.trip.findUnique).toHaveBeenCalledWith({
        where: { inviteCode: 'abc123' },
        select: {
          name: true,
          coverImageUrl: true,
          status: true,
          _count: {
            select: {
              members: { where: { inviteStatus: InviteStatus.ACCEPTED } },
            },
          },
        },
      });
      expect(storageService.getSignedThumbUrl).toHaveBeenCalledWith(
        'trip-covers/abc123',
      );
      expect(result).toEqual({
        name: 'Trip to Dubai',
        coverImageUrl: 'https://signed.example/trip-covers/abc123',
        memberCount: 4,
        status: 'PLANNING',
      });
    });

    it('should throw NotFoundException for invalid invite code', async () => {
      prisma.trip.findUnique.mockResolvedValue(null);

      await expect(service.getInvitePreview('invalid')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should return null cover image when trip has no cover key', async () => {
      prisma.trip.findUnique.mockResolvedValue({
        name: 'Trip to Da Lat',
        coverImageUrl: null,
        status: 'PLANNING',
        _count: { members: 2 },
      });

      const result = await service.getInvitePreview('abc123');

      expect(storageService.getSignedThumbUrl).not.toHaveBeenCalled();
      expect(result).toEqual({
        name: 'Trip to Da Lat',
        coverImageUrl: null,
        memberCount: 2,
        status: 'PLANNING',
      });
    });
  });

  describe('respondToInvite', () => {
    it('should accept a pending invitation', async () => {
      prisma.tripMember.findUnique.mockResolvedValue({
        ...mockMember,
        inviteStatus: InviteStatus.PENDING,
      });
      prisma.tripMember.update.mockResolvedValue({
        ...mockMember,
        inviteStatus: InviteStatus.ACCEPTED,
        user: { id: 1, displayName: 'Test User', avatarUrl: null },
      });

      const result = await service.respondToInvite(1, 1, {
        status: 'ACCEPTED',
      });

      expect(prisma.tripMember.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            inviteStatus: 'ACCEPTED',
          }),
        }),
      );
      expect(result.inviteStatus).toBe(InviteStatus.ACCEPTED);
    });

    it('should decline a pending invitation', async () => {
      prisma.tripMember.findUnique.mockResolvedValue({
        ...mockMember,
        inviteStatus: InviteStatus.PENDING,
      });
      prisma.tripMember.update.mockResolvedValue({
        ...mockMember,
        inviteStatus: InviteStatus.DECLINED,
        joinedAt: null,
        user: { id: 1, displayName: 'Test User', avatarUrl: null },
      });

      const result = await service.respondToInvite(1, 1, {
        status: 'DECLINED',
      });

      expect(result.inviteStatus).toBe(InviteStatus.DECLINED);
    });

    it('should throw BadRequestException if already responded', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockMember); // ACCEPTED

      await expect(
        service.respondToInvite(1, 1, { status: 'ACCEPTED' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should throw NotFoundException if no invitation exists', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(null);

      await expect(
        service.respondToInvite(1, 99, { status: 'ACCEPTED' }),
      ).rejects.toThrow(NotFoundException);
    });

    // A lapsed Google Play subscriber can sit at stored ACTIVE forever (no
    // RTDN wired). TripMemberDto.isPro gates a real entitlement on Android
    // (receipt-scan paywall bypass) — it must not trust the raw stored
    // status the way the display-only isUserPro() in auth/friends.service.ts
    // does.
    it('member with stored ACTIVE + past subscriptionExpiresAt serializes isPro=false', async () => {
      prisma.tripMember.findUnique.mockResolvedValue({
        ...mockMember,
        inviteStatus: InviteStatus.PENDING,
      });
      prisma.tripMember.update.mockResolvedValue({
        ...mockMember,
        inviteStatus: InviteStatus.ACCEPTED,
        user: {
          id: 1,
          displayName: 'Test User',
          avatarUrl: null,
          friendCode: null,
          subscriptionStatus: SubscriptionStatus.ACTIVE,
          subscriptionExpiresAt: new Date(Date.now() - 86400000),
        },
      });

      const result = await service.respondToInvite(1, 1, {
        status: 'ACCEPTED',
      });

      expect(result.isPro).toBe(false);
    });

    it('member with stored ACTIVE + future subscriptionExpiresAt still serializes isPro=true', async () => {
      prisma.tripMember.findUnique.mockResolvedValue({
        ...mockMember,
        inviteStatus: InviteStatus.PENDING,
      });
      prisma.tripMember.update.mockResolvedValue({
        ...mockMember,
        inviteStatus: InviteStatus.ACCEPTED,
        user: {
          id: 1,
          displayName: 'Test User',
          avatarUrl: null,
          friendCode: null,
          subscriptionStatus: SubscriptionStatus.ACTIVE,
          subscriptionExpiresAt: new Date(Date.now() + 86400000),
        },
      });

      const result = await service.respondToInvite(1, 1, {
        status: 'ACCEPTED',
      });

      expect(result.isPro).toBe(true);
      expect(prisma.user.updateMany).not.toHaveBeenCalled();
    });
  });

  describe('removeMember', () => {
    it('should allow creator to remove another member', async () => {
      prisma.trip.findUnique.mockResolvedValue({ createdById: 1 });
      prisma.user.findUnique.mockResolvedValue({ displayName: 'User 10' });
      prisma.tripMember.findUnique.mockResolvedValue({
        vaultLeaveClearedAt: null,
      });
      prisma.tripMember.delete.mockResolvedValue({});

      await service.removeMember(1, 10, 1);

      expect(prisma.tripMember.delete).toHaveBeenCalledWith({
        where: { tripId_userId: { tripId: 1, userId: 10 } },
      });
    });

    it('should allow a member to leave (remove self)', async () => {
      prisma.trip.findUnique.mockResolvedValue({ createdById: 1 });
      prisma.user.findUnique.mockResolvedValue({ displayName: 'User 10' });
      prisma.tripMember.findUnique.mockResolvedValue({
        vaultLeaveClearedAt: null,
      });
      prisma.tripMember.delete.mockResolvedValue({});

      await service.removeMember(1, 10, 10);

      expect(prisma.tripMember.delete).toHaveBeenCalledWith({
        where: { tripId_userId: { tripId: 1, userId: 10 } },
      });
    });

    it('should throw BadRequestException when trying to remove the creator', async () => {
      prisma.trip.findUnique.mockResolvedValue({ createdById: 1 });

      await expect(service.removeMember(1, 1, 1)).rejects.toThrow(
        BadRequestException,
      );
    });

    it('should throw ForbiddenException when non-creator tries to remove others', async () => {
      prisma.trip.findUnique.mockResolvedValue({ createdById: 1 });

      await expect(service.removeMember(1, 10, 5)).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('should throw NotFoundException when trip does not exist', async () => {
      prisma.trip.findUnique.mockResolvedValue(null);

      await expect(service.removeMember(999, 10, 1)).rejects.toThrow(
        NotFoundException,
      );
    });
  });
});
