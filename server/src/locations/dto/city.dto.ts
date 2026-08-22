import { ApiProperty } from '@nestjs/swagger';

export class CityDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  name: string;

  @ApiProperty({ type: 'string' })
  latitude: string;

  @ApiProperty({ type: 'string' })
  longitude: string;
}

export class CityPageDto {
  data: CityDto[];

  /** Cursor for the next page, or null if no more results */
  @ApiProperty({ type: 'integer', nullable: true })
  nextCursor: number | null;
}
