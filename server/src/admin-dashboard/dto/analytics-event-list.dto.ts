import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { AnalyticsEventName } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  IsEnum,
  IsIn,
  IsInt,
  IsISO8601,
  IsOptional,
  Max,
  Min,
} from 'class-validator';

const VALID_PLATFORMS = ['ios', 'android', 'web', 'unknown'] as const;

export class AdminAnalyticsEventListQueryDto {
  @ApiPropertyOptional({ type: 'integer', minimum: 1, default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({
    type: 'integer',
    minimum: 1,
    maximum: 200,
    default: 50,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number = 50;

  @ApiPropertyOptional({
    enum: AnalyticsEventName,
    enumName: 'AnalyticsEventName',
  })
  @IsOptional()
  @IsEnum(AnalyticsEventName)
  eventName?: AnalyticsEventName;

  @ApiPropertyOptional({ type: 'integer' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  userId?: number;

  @ApiPropertyOptional({
    description: 'ISO 8601 date (inclusive lower bound).',
  })
  @IsOptional()
  @IsISO8601()
  from?: string;

  @ApiPropertyOptional({
    description: 'ISO 8601 date (inclusive upper bound).',
  })
  @IsOptional()
  @IsISO8601()
  to?: string;

  @ApiPropertyOptional({
    description: 'Filter by platform: ios, android, web, or unknown.',
    enum: VALID_PLATFORMS,
  })
  @IsOptional()
  @IsIn(VALID_PLATFORMS)
  platform?: string;
}

export class AdminAnalyticsEventDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ enum: AnalyticsEventName, enumName: 'AnalyticsEventName' })
  eventName: AnalyticsEventName;

  @ApiProperty()
  occurredAt: Date;

  @ApiPropertyOptional({ type: 'integer', nullable: true })
  userId: number | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  userEmail: string | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  sessionId: string | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  platform: string | null;

  @ApiPropertyOptional({
    nullable: true,
    type: 'object',
    additionalProperties: true,
  })
  properties: Record<string, unknown> | null;
}

export class AdminAnalyticsEventListResponseDto {
  @ApiProperty({ type: [AdminAnalyticsEventDto] })
  items: AdminAnalyticsEventDto[];

  @ApiProperty({ type: 'integer' })
  total: number;

  @ApiProperty({ type: 'integer' })
  page: number;

  @ApiProperty({ type: 'integer' })
  limit: number;
}
