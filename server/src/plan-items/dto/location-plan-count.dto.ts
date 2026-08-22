import { ApiProperty } from '@nestjs/swagger';

export class LocationPlanCountDto {
  @ApiProperty({ description: 'Location name that was queried' })
  location: string;

  @ApiProperty({
    type: 'integer',
    description: 'Number of times this location has been added to plans',
  })
  count: number;
}
