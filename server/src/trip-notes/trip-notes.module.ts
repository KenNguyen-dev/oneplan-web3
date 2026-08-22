import { Module } from '@nestjs/common';
import { TripNotesController } from './trip-notes.controller';
import { TripNotesService } from './trip-notes.service';

@Module({
  controllers: [TripNotesController],
  providers: [TripNotesService],
})
export class TripNotesModule {}
