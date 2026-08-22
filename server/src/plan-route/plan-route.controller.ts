import { Controller, Get, Param, ParseIntPipe, Query } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiForbiddenResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { PlanRouteQueryDto } from './dto/plan-route-query.dto';
import { PlanRouteDto } from './dto/plan-route.dto';
import { PlanRouteService } from './plan-route.service';

@ApiBearerAuth()
@ApiTags('Plan Route')
@Controller('trips/:tripId/plan-route')
export class PlanRouteController {
  constructor(private readonly planRouteService: PlanRouteService) {}

  @Get()
  @ApiOperation({
    operationId: 'getPlanRoute',
    summary: 'Get ordered map pins and driving-route legs for a trip day',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiOkResponse({ type: PlanRouteDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  getPlanRoute(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Query() query: PlanRouteQueryDto,
  ): Promise<PlanRouteDto> {
    return this.planRouteService.getPlanRoute(tripId, userId, query.date);
  }
}
