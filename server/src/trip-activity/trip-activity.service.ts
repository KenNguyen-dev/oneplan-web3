import { Injectable, Logger } from '@nestjs/common';
import { ActivityAction } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class TripActivityService {
  private readonly logger = new Logger(TripActivityService.name);

  constructor(private readonly prisma: PrismaService) {}

  async log(
    tripId: number,
    userId: number,
    action: ActivityAction,
    targetId?: number,
    metadata?: Record<string, any>,
  ): Promise<void> {
    try {
      await this.prisma.tripActivity.create({
        data: {
          tripId,
          userId,
          action,
          targetId,
          metadata,
          createdAt: new Date(),
        },
      });
    } catch (error) {
      this.logger.warn(
        `Failed to log activity ${action} for trip ${tripId}: ${error}`,
      );
    }
  }
}
