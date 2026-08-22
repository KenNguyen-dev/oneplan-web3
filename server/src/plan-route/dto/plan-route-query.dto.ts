import { ApiProperty } from '@nestjs/swagger';
import { Matches } from 'class-validator';

export class PlanRouteQueryDto {
  @ApiProperty({ description: 'ISO date string (YYYY-MM-DD)' })
  @Matches(/^\d{4}-\d{2}-\d{2}$/, {
    message: 'date must be in YYYY-MM-DD format',
  })
  date: string;
}
