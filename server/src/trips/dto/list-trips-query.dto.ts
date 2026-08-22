import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsEnum, IsOptional } from 'class-validator';
import { TripStatus } from '@prisma/client';

export class ListTripsQueryDto {
  @ApiPropertyOptional({ enum: TripStatus, enumName: 'TripStatus' })
  @IsOptional()
  @IsEnum(TripStatus)
  status?: TripStatus;
}
