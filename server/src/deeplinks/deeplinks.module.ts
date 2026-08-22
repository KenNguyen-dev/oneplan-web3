import { Module } from '@nestjs/common';
import { FriendsModule } from '../friends/friends.module';
import { MarketplaceModule } from '../marketplace/marketplace.module';
import { TripsModule } from '../trips/trips.module';
import { DeeplinksController } from './deeplinks.controller';

@Module({
  imports: [FriendsModule, TripsModule, MarketplaceModule],
  controllers: [DeeplinksController],
})
export class DeeplinksModule {}
