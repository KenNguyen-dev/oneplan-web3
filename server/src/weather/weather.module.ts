import { Module } from '@nestjs/common';
import { WeatherService } from './weather.service';

// PrismaModule and ConfigModule are @Global, so only the service is declared.
@Module({
  providers: [WeatherService],
  exports: [WeatherService],
})
export class WeatherModule {}
