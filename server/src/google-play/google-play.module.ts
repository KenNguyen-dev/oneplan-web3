import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { GooglePlayPurchaseClient } from './google-play-purchase-client';

/**
 * Owns the shared Google Play Android Publisher REST client. Imported by both
 * the subscription and marketplace modules so their Play verifiers delegate to
 * a single implementation (access tokens, get/acknowledge, validation).
 */
@Module({
  imports: [ConfigModule],
  providers: [GooglePlayPurchaseClient],
  exports: [GooglePlayPurchaseClient],
})
export class GooglePlayModule {}
