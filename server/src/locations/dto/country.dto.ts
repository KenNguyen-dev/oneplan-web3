import { ApiProperty } from '@nestjs/swagger';

export class CountryDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  name: string;
  iso2: string | null;
  iso3: string | null;
  phoneCode: string | null;
  capital: string | null;
  currency: string | null;
  region: string | null;
  subRegion: string | null;
  emoji: string | null;
}
