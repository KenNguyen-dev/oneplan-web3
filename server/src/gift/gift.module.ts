import { Module } from '@nestjs/common';
import { AdminGuard } from '../auth/guards/admin.guard';
import { ScanCreditModule } from '../scan-credit/scan-credit.module';
import { GiftController } from './gift.controller';
import { GiftService } from './gift.service';

// Admin-only loyalty gifting: grant scan credits (via ScanCreditService) and/or
// a Pro package by email. PrismaModule is @Global.
@Module({
  imports: [ScanCreditModule],
  controllers: [GiftController],
  providers: [GiftService, AdminGuard],
})
export class GiftModule {}
