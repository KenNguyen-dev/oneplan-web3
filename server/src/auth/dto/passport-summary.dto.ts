import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class PassportCityStatDto {
  @ApiProperty()
  name: string;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class PassportCountryStatDto {
  @ApiProperty()
  name: string;

  @ApiPropertyOptional()
  emoji: string | null;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class PassportSummaryDto {
  @ApiProperty()
  displayName: string;

  @ApiProperty()
  email: string;

  @ApiPropertyOptional()
  avatarUrl: string | null;

  @ApiProperty()
  memberSince: string;

  @ApiProperty({ type: 'integer' })
  tripsCount: number;

  @ApiProperty({ type: 'integer' })
  countriesCount: number;

  @ApiProperty({ type: 'integer' })
  citiesCount: number;

  @ApiProperty({ type: [PassportCityStatDto] })
  topCities: PassportCityStatDto[];

  @ApiProperty({ type: [PassportCountryStatDto] })
  topCountries: PassportCountryStatDto[];
}
