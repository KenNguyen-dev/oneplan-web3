import { Module } from '@nestjs/common';
import { BudgetsModule } from '../budgets/budgets.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PlanItemsModule } from '../plan-items/plan-items.module';
import { TripVaultModule } from '../trip-vault/trip-vault.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { StorageModule } from '../storage/storage.module';
import { TripEndConsensusService } from './trip-end-consensus.service';
import { TripsController } from './trips.controller';
import { TripsService } from './trips.service';

@Module({
  imports: [
    StorageModule,
    BudgetsModule,
    RealtimeModule,
    NotificationsModule,
    PlanItemsModule,
    TripVaultModule,
  ],
  controllers: [TripsController],
  providers: [TripsService, TripEndConsensusService],
  exports: [TripsService],
})
export class TripsModule {}
