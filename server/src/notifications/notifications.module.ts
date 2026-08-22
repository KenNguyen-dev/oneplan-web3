import { Module } from '@nestjs/common';
import { NotificationsController } from './notifications.controller';
import { NotificationsAdminController } from './notifications-admin.controller';
import { NotificationsService } from './notifications.service';
import { ApnsPushAdapter } from './adapters/apns-push.adapter';
import { FcmPushAdapter } from './adapters/fcm-push.adapter';
import { AdminGuard } from '../auth/guards/admin.guard';

@Module({
  controllers: [NotificationsController, NotificationsAdminController],
  providers: [
    NotificationsService,
    ApnsPushAdapter,
    FcmPushAdapter,
    AdminGuard,
  ],
  exports: [NotificationsService],
})
export class NotificationsModule {}
