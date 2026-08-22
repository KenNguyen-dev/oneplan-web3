import { Module } from '@nestjs/common';
import { RecentLocationsController } from './recent-locations.controller';
import { RecentLocationsService } from './recent-locations.service';

@Module({
  controllers: [RecentLocationsController],
  providers: [RecentLocationsService],
})
export class RecentLocationsModule {}
