import { Controller, Get, Query } from '@nestjs/common';
import { ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../auth/decorators/public.decorator';
import { LocationSearchResultDto } from './dto/location-search-result.dto';
import { SearchLocationsQueryDto } from './dto/search-locations-query.dto';
import { LocationsService } from './locations.service';

@Public()
@ApiTags('Locations')
@Controller('locations')
export class LocationsController {
  constructor(private readonly locationsService: LocationsService) {}

  @Get('search')
  @ApiOperation({
    operationId: 'searchLocations',
    summary: 'Search cities and states for trip location selection',
  })
  @ApiOkResponse({ type: [LocationSearchResultDto] })
  search(@Query() query: SearchLocationsQueryDto) {
    return this.locationsService.searchLocations(
      query.search,
      query.take ?? 50,
    );
  }
}
