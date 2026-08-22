import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsDateString, IsInt, IsOptional, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class ListPlanItemsQueryDto {
  @ApiPropertyOptional({ description: 'ISO date string (YYYY-MM-DD)' })
  @IsOptional()
  @IsDateString()
  planDate?: string;

  @ApiPropertyOptional({
    type: 'integer',
    minimum: 1,
    description: 'Relative day number (1-based)',
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  dayNumber?: number;
}
