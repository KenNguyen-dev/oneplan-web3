import { Module } from '@nestjs/common';
import { AdminGuard } from '../auth/guards/admin.guard';
import { AnalyticsModule } from '../analytics/analytics.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { TripRequestsAdminController } from './trip-requests-admin.controller';
import { TripRequestsController } from './trip-requests.controller';
import { TripRequestsService } from './trip-requests.service';

@Module({
  imports: [AnalyticsModule, NotificationsModule],
  controllers: [TripRequestsController, TripRequestsAdminController],
  providers: [TripRequestsService, AdminGuard],
})
export class TripRequestsModule {}
