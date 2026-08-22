import { Module } from '@nestjs/common';
import { StorageModule } from '../storage/storage.module';
import { TripPhotosController } from './trip-photos.controller';
import { TripPhotosService } from './trip-photos.service';

@Module({
  imports: [StorageModule],
  controllers: [TripPhotosController],
  providers: [TripPhotosService],
})
export class TripPhotosModule {}
