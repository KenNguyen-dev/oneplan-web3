import { Module } from '@nestjs/common';
import { MarketplaceController } from './marketplace.controller';
import { MarketplaceAdminController } from './marketplace-admin.controller';
import { MarketplaceService } from './marketplace.service';
import { AdminGuard } from '../auth/guards/admin.guard';
import { StorageModule } from '../storage/storage.module';
import { TripsModule } from '../trips/trips.module';
import { MarketplacePurchaseVerifierService } from './marketplace-purchase-verifier.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { GooglePlayModule } from '../google-play/google-play.module';

@Module({
  imports: [StorageModule, TripsModule, NotificationsModule, GooglePlayModule],
  controllers: [MarketplaceController, MarketplaceAdminController],
  providers: [
    MarketplaceService,
    MarketplacePurchaseVerifierService,
    AdminGuard,
  ],
  exports: [MarketplaceService],
})
export class MarketplaceModule {}
