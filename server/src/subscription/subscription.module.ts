import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { GooglePlayModule } from '../google-play/google-play.module';
import { ScanCreditModule } from '../scan-credit/scan-credit.module';
import { GooglePlaySubscriptionVerifierService } from './google-play-subscription-verifier.service';
import { SubscriptionController } from './subscription.controller';
import { SubscriptionService } from './subscription.service';
import { EntitlementService } from './entitlement/entitlement.service';
import { StoreEventProcessor } from './store-event/store-event.processor';
import { AppleStoreAdapter } from './adapters/apple-store.adapter';
import { PlayStoreAdapter } from './adapters/play-store.adapter';

@Module({
  imports: [ConfigModule, ScanCreditModule, GooglePlayModule],
  controllers: [SubscriptionController],
  providers: [
    SubscriptionService,
    GooglePlaySubscriptionVerifierService,
    EntitlementService,
    StoreEventProcessor,
    AppleStoreAdapter,
    PlayStoreAdapter,
  ],
  exports: [
    SubscriptionService,
    EntitlementService,
    StoreEventProcessor,
    AppleStoreAdapter,
    PlayStoreAdapter,
  ],
})
export class SubscriptionModule {}
