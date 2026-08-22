import { ApiProperty } from '@nestjs/swagger';
import { PlanRoutePinDto } from './plan-route-pin.dto';
import { PlanRouteLegDto } from './plan-route-leg.dto';

export class PlanRouteDto {
  @ApiProperty({ type: [PlanRoutePinDto] })
  pins: PlanRoutePinDto[];

  @ApiProperty({ type: [PlanRouteLegDto] })
  legs: PlanRouteLegDto[];
}
