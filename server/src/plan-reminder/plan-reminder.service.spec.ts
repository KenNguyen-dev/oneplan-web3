import { Test, TestingModule } from '@nestjs/testing';
import { TripStatus } from '@prisma/client';
import { PlanReminderService } from './plan-reminder.service';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';

describe('PlanReminderService', () => {
  let service: PlanReminderService;
  let prisma: jest.Mocked<PrismaService>;
  let notifications: jest.Mocked<NotificationsService>;

  beforeEach(async () => {
    const mockPrisma = {
      tripPlanItem: {
        findMany: jest.fn(),
        update: jest.fn(),
      },
    };

    const mockNotifications = {
      sendPlanReminderPush: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PlanReminderService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: NotificationsService, useValue: mockNotifications },
      ],
    }).compile();

    service = module.get<PlanReminderService>(PlanReminderService);
    prisma = module.get(PrismaService);
    notifications = module.get(NotificationsService);
  });

  describe('checkUpcomingPlans', () => {
    it('should send notification and mark notifiedAt for eligible items', async () => {
      const mockItem = {
        id: 1,
        title: 'Visit Coffee Farm',
        startTime: '09:45',
        location: 'Cau Dat Farm',
        planDate: new Date('2026-04-13'),
        notifiedAt: null,
        trip: {
          id: 10,
          name: 'Da Lat Adventure',
          country: {
            id: 1,
            timezones: '[{"zoneName":"Asia/Ho_Chi_Minh"}]',
          },
        },
        members: [{ userId: 100 }, { userId: 101 }],
      };

      prisma.tripPlanItem.findMany.mockResolvedValue([mockItem]);
      prisma.tripPlanItem.update.mockResolvedValue({
        ...mockItem,
        notifiedAt: new Date(),
      });
      notifications.sendPlanReminderPush.mockResolvedValue();

      // Mock the current time to be 45 minutes before startTime
      jest.useFakeTimers();
      jest.setSystemTime(new Date('2026-04-13T02:00:00Z')); // 09:00 in Vietnam

      await service.checkUpcomingPlans();

      expect(notifications.sendPlanReminderPush).toHaveBeenCalledWith(
        {
          id: 1,
          title: 'Visit Coffee Farm',
          startTime: '09:45',
          location: 'Cau Dat Farm',
        },
        10,
        'Da Lat Adventure',
        [100, 101],
      );

      expect(prisma.tripPlanItem.update).toHaveBeenCalledWith({
        where: { id: 1 },
        data: { notifiedAt: expect.any(Date) },
      });

      jest.useRealTimers();
    });

    it('should skip items without country', async () => {
      const mockItem = {
        id: 1,
        title: 'Test',
        startTime: '09:45',
        location: null,
        planDate: new Date('2026-04-13'),
        notifiedAt: null,
        trip: {
          id: 10,
          name: 'Trip',
          country: null,
        },
        members: [{ userId: 100 }],
      };

      prisma.tripPlanItem.findMany.mockResolvedValue([mockItem]);

      jest.useFakeTimers();
      jest.setSystemTime(new Date('2026-04-13T02:00:00Z'));

      await service.checkUpcomingPlans();

      expect(notifications.sendPlanReminderPush).not.toHaveBeenCalled();
      expect(prisma.tripPlanItem.update).not.toHaveBeenCalled();

      jest.useRealTimers();
    });

    it('should exclude ended trips from the query', async () => {
      prisma.tripPlanItem.findMany.mockResolvedValue([]);

      jest.useFakeTimers();
      jest.setSystemTime(new Date('2026-04-13T02:00:00Z'));

      await service.checkUpcomingPlans();

      expect(prisma.tripPlanItem.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            trip: { status: { not: TripStatus.ENDED } },
          }),
        }),
      );

      jest.useRealTimers();
    });

    it('should skip items with invalid timezone', async () => {
      const mockItem = {
        id: 1,
        title: 'Test',
        startTime: '09:45',
        location: null,
        planDate: new Date('2026-04-13'),
        notifiedAt: null,
        trip: {
          id: 10,
          name: 'Trip',
          country: {
            id: 1,
            timezones: 'invalid-json',
          },
        },
        members: [{ userId: 100 }],
      };

      prisma.tripPlanItem.findMany.mockResolvedValue([mockItem]);

      jest.useFakeTimers();
      jest.setSystemTime(new Date('2026-04-13T02:00:00Z'));

      await service.checkUpcomingPlans();

      expect(notifications.sendPlanReminderPush).not.toHaveBeenCalled();

      jest.useRealTimers();
    });
  });
});
