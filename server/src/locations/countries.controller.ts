import { Controller, Get, Param, ParseIntPipe } from '@nestjs/common';
import {
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { Public } from '../auth/decorators/public.decorator';
import { LocationsService } from './locations.service';
import { CountryDto } from './dto/country.dto';
import { StateDto } from './dto/state.dto';

@Public()
@ApiTags('Countries')
@Controller('countries')
export class CountriesController {
  constructor(private readonly locationsService: LocationsService) {}

  @Get()
  @ApiOperation({ operationId: 'listCountries', summary: 'List all countries' })
  @ApiOkResponse({ type: [CountryDto] })
  findAll() {
    return this.locationsService.findAllCountries();
  }

  @Get(':id/states')
  @ApiOperation({
    operationId: 'listStatesByCountry',
    summary: 'List states/provinces for a country',
  })
  @ApiParam({ name: 'id', type: 'integer', description: 'Country ID' })
  @ApiOkResponse({ type: [StateDto] })
  findStates(@Param('id', ParseIntPipe) id: number) {
    return this.locationsService.findStatesByCountry(id);
  }
}
