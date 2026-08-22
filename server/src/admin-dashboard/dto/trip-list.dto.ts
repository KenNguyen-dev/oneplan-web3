import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Currency, TripStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { AdminSortDir } from './user-list.dto';

export enum AdminTripSortBy {
  createdAt = 'createdAt',
  members = 'members',
  expenses = 'expenses',
  startDate = 'startDate',
}

export class AdminTripListQueryDto {
  @ApiPropertyOptional({ type: 'integer', minimum: 1, default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({
    type: 'integer',
    minimum: 1,
    maximum: 100,
    default: 25,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 25;

  @ApiPropertyOptional({ description: 'Match against trip name.' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  search?: string;

  @ApiPropertyOptional({ enum: TripStatus, enumName: 'TripStatus' })
  @IsOptional()
  @IsEnum(TripStatus)
  status?: TripStatus;

  @ApiPropertyOptional({
    enum: AdminTripSortBy,
    enumName: 'AdminTripSortBy',
    default: AdminTripSortBy.createdAt,
  })
  @IsOptional()
  @IsEnum(AdminTripSortBy)
  sortBy?: AdminTripSortBy = AdminTripSortBy.createdAt;

  @ApiPropertyOptional({
    enum: AdminSortDir,
    enumName: 'AdminSortDir',
    default: AdminSortDir.desc,
  })
  @IsOptional()
  @IsEnum(AdminSortDir)
  sortDir?: AdminSortDir = AdminSortDir.desc;
}

export class AdminTripSummaryDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  name: string;

  @ApiProperty({ enum: TripStatus, enumName: 'TripStatus' })
  status: TripStatus;

  @ApiProperty()
  creatorEmail: string;

  @ApiProperty()
  creatorName: string;

  @ApiProperty({ type: 'integer' })
  memberCount: number;

  @ApiProperty({ type: 'integer' })
  expenseCount: number;

  @ApiProperty({ enum: Currency, enumName: 'Currency' })
  currency: Currency;

  @ApiPropertyOptional({ nullable: true, type: Date })
  startDate: Date | null;

  @ApiPropertyOptional({ nullable: true, type: Date })
  endDate: Date | null;

  @ApiProperty()
  createdAt: Date;
}

export class AdminTripListResponseDto {
  @ApiProperty({ type: [AdminTripSummaryDto] })
  items: AdminTripSummaryDto[];

  @ApiProperty({ type: 'integer' })
  total: number;

  @ApiProperty({ type: 'integer' })
  page: number;

  @ApiProperty({ type: 'integer' })
  limit: number;
}
