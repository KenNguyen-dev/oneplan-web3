import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class RecentLocationDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  name: string;

  @ApiPropertyOptional()
  address: string | null;

  @ApiPropertyOptional({ type: 'number' })
  latitude: number | null;

  @ApiPropertyOptional({ type: 'number' })
  longitude: number | null;

  @ApiPropertyOptional()
  pointOfInterestCategory: string | null;

  @ApiProperty()
  lastViewedAt: string;
}
