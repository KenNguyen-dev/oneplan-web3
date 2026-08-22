import { Module } from '@nestjs/common';
import { GeminiModule } from '../common/gemini/gemini.module';
import { LocationsModule } from '../locations/locations.module';
import { MarketplaceModule } from '../marketplace/marketplace.module';
import { StorageModule } from '../storage/storage.module';
import { TripGeneratorController } from './trip-generator.controller';
import { TripGeneratorService } from './trip-generator.service';

// AI trip generation for authenticated dashboard users: Gemini itinerary ->
// Apple Maps place links -> OnePlan-template CSV / image ZIP / marketplace
// listing creation. MarketplaceModule provides listing + item creation,
// StorageModule provides server-side image upload. LocationsModule resolves
// the destination to city/state/country ids so created listings are
// pre-filled for admin review.
@Module({
  imports: [GeminiModule, LocationsModule, MarketplaceModule, StorageModule],
  controllers: [TripGeneratorController],
  providers: [TripGeneratorService],
})
export class TripGeneratorModule {}
