import { Module } from '@nestjs/common';
import { AdminGuard } from '../auth/guards/admin.guard';
import { AdminDashboardController } from './admin-dashboard.controller';
import { AdminDashboardService } from './admin-dashboard.service';

@Module({
  controllers: [AdminDashboardController],
  providers: [AdminDashboardService, AdminGuard],
})
export class AdminDashboardModule {}
