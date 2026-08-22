import { Global, Module } from '@nestjs/common';
import { TripActivityService } from './trip-activity.service';

@Global()
@Module({
  providers: [TripActivityService],
  exports: [TripActivityService],
})
export class TripActivityModule {}
