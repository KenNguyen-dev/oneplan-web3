import { Controller, Get, Query } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOkResponse,
  ApiOperation,
  ApiQuery,
  ApiTags,
} from '@nestjs/swagger';
import { PlanItemsService } from './plan-items.service';
import { LocationPlanCountDto } from './dto/location-plan-count.dto';

@ApiBearerAuth()
@ApiTags('Plan Items')
@Controller('plan-items/stats')
export class PlanItemStatsController {
  constructor(private readonly planItemsService: PlanItemsService) {}

  @Get('location-plan-count')
  @ApiOperation({
    operationId: 'getLocationPlanCount',
    summary: 'Get how many times a location has been added to plans',
  })
  @ApiQuery({
    name: 'location',
    type: 'string',
    description: 'Location name to look up',
  })
  @ApiOkResponse({ type: LocationPlanCountDto })
  getLocationPlanCount(
    @Query('location') location: string,
  ): Promise<LocationPlanCountDto> {
    return this.planItemsService.getLocationPlanCount(location);
  }
}
