import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScanCreditController } from './scan-credit.controller';
import { ScanCreditService } from './scan-credit.service';

// Cross-cutting credit ledger used by Board (consume/refund), Auth (signup
// bonus), and Subscription (Pro weekly reconcile + purchase grants). Also
// exposes POST /scan-credit/app-launch for the per-version app-update reward.
// PrismaModule is @Global, so only ConfigModule needs importing here.
@Module({
  imports: [ConfigModule],
  controllers: [ScanCreditController],
  providers: [ScanCreditService],
  exports: [ScanCreditService],
})
export class ScanCreditModule {}
