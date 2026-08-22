import { Controller, Get, Param, ParseIntPipe, Query } from '@nestjs/common';
import {
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { Public } from '../auth/decorators/public.decorator';
import { LocationsService } from './locations.service';
import { CityPageDto } from './dto/city.dto';
import { FindCitiesQueryDto } from './dto/find-cities-query.dto';

@Public()
@ApiTags('States')
@Controller('states')
export class StatesController {
  constructor(private readonly locationsService: LocationsService) {}

  @Get(':id/cities')
  @ApiOperation({
    operationId: 'listCitiesByState',
    summary: 'List cities in a state with cursor pagination',
  })
  @ApiParam({ name: 'id', type: 'integer', description: 'State ID' })
  @ApiOkResponse({ type: CityPageDto })
  findCities(
    @Param('id', ParseIntPipe) id: number,
    @Query() query: FindCitiesQueryDto,
  ) {
    return this.locationsService.findCitiesByState(
      id,
      query.search,
      query.cursor,
      query.take ?? 50,
    );
  }
}
