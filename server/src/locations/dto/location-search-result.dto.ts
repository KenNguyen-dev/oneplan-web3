import { ApiProperty } from '@nestjs/swagger';
import { CityDto } from './city.dto';
import { CountryDto } from './country.dto';
import { StateDto } from './state.dto';

export class LocationSearchResultDto {
  @ApiProperty({ type: CityDto, nullable: true })
  city: CityDto | null;

  @ApiProperty({ type: StateDto })
  state: StateDto;

  @ApiProperty({ type: CountryDto })
  country: CountryDto;
}
