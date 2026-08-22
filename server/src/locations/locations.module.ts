import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { CountriesController } from './countries.controller';
import { CurrenciesController } from './currencies.controller';
import { LocationsController } from './locations.controller';
import { StatesController } from './states.controller';
import { LocationsService } from './locations.service';

@Module({
  imports: [PrismaModule],
  controllers: [
    CountriesController,
    CurrenciesController,
    LocationsController,
    StatesController,
  ],
  providers: [LocationsService],
  exports: [LocationsService],
})
export class LocationsModule {}
