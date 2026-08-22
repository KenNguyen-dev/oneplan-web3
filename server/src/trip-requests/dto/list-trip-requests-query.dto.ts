import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';
import { TripRequestStatus } from '@prisma/client';

export class ListTripRequestsQueryDto {
  @ApiPropertyOptional({
    enum: TripRequestStatus,
    enumName: 'TripRequestStatus',
    description: 'Filter by status. Omit to list all statuses.',
  })
  @IsOptional()
  @IsEnum(TripRequestStatus)
  status?: TripRequestStatus;

  @ApiPropertyOptional({ type: 'integer', default: 1, minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @ApiPropertyOptional({
    type: 'integer',
    default: 50,
    minimum: 1,
    maximum: 200,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  pageSize?: number;
}
