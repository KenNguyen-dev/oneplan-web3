import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { PlanReminderService } from './plan-reminder.service';

@Module({
  imports: [NotificationsModule],
  providers: [PlanReminderService],
})
export class PlanReminderModule {}
