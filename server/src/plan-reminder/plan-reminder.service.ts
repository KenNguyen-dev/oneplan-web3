import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { TripStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { parseTimezone, isInNotificationWindow } from '../common/timezone.util';

@Injectable()
export class PlanReminderService {
  private readonly logger = new Logger(PlanReminderService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
  ) {}

  @Cron('*/5 * * * *')
  async checkUpcomingPlans(): Promise<void> {
    const now = new Date();
    const today = new Date(now);
    today.setHours(0, 0, 0, 0);

    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);

    const items = await this.prisma.tripPlanItem.findMany({
      where: {
        planDate: {
          gte: yesterday,
          lte: tomorrow,
        },
        startTime: { not: null },
        notifiedAt: null,
        trip: {
          status: { not: TripStatus.ENDED },
        },
      },
      include: {
        trip: {
          select: {
            id: true,
            name: true,
            country: {
              select: {
                id: true,
                timezones: true,
              },
            },
          },
        },
        members: {
          select: { userId: true },
        },
      },
    });

    let notificationCount = 0;

    for (const item of items) {
      if (!item.trip.country) {
        continue;
      }

      const timezone = parseTimezone(item.trip.country.timezones);
      if (!timezone) {
        this.logger.warn(
          `Invalid timezone for country ${item.trip.country.id}, skipping item ${item.id}`,
        );
        continue;
      }

      if (
        !isInNotificationWindow(item.planDate!, item.startTime!, timezone, now)
      ) {
        continue;
      }

      const memberUserIds = item.members.map((m) => m.userId);
      if (memberUserIds.length === 0) {
        continue;
      }

      try {
        await this.notifications.sendPlanReminderPush(
          {
            id: item.id,
            title: item.title,
            startTime: item.startTime!,
            location: item.location,
          },
          item.trip.id,
          item.trip.name,
          memberUserIds,
        );

        await this.prisma.tripPlanItem.update({
          where: { id: item.id },
          data: { notifiedAt: now },
        });

        notificationCount++;
      } catch (error) {
        this.logger.error(
          `Failed to send notification for item ${item.id}: ${error}`,
        );
        // Still mark as notified to avoid retry spam
        await this.prisma.tripPlanItem.update({
          where: { id: item.id },
          data: { notifiedAt: now },
        });
      }
    }

    if (notificationCount > 0) {
      this.logger.log(`Sent ${notificationCount} plan reminder(s)`);
    }
  }
}
