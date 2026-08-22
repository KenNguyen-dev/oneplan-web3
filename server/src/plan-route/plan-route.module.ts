import { Module } from '@nestjs/common';
import { PlanRouteController } from './plan-route.controller';
import { PlanRouteService } from './plan-route.service';

@Module({
  controllers: [PlanRouteController],
  providers: [PlanRouteService],
  exports: [PlanRouteService],
})
export class PlanRouteModule {}
