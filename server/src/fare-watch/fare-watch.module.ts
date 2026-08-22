import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { ZaloModule } from '../common/zalo/zalo.module';
import { FareClickController } from './fare-click.controller';
import { FareWatchController } from './fare-watch.controller';
import { FareWatchService } from './fare-watch.service';
import { FareWatchEngineService } from './fare-watch-engine.service';
import { TravelpayoutsService } from './travelpayouts.service';

@Module({
  imports: [PrismaModule, ZaloModule],
  controllers: [FareWatchController, FareClickController],
  providers: [FareWatchService, FareWatchEngineService, TravelpayoutsService],
  exports: [FareWatchService],
})
export class FareWatchModule {}
