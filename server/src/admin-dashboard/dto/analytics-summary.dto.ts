import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { AnalyticsEventName } from '@prisma/client';
import { IsISO8601, IsOptional } from 'class-validator';

export class AdminAnalyticsSummaryQueryDto {
  @ApiPropertyOptional({
    description:
      'ISO 8601 date. Defaults to 30 days before `to`. Window is capped at 365 days.',
  })
  @IsOptional()
  @IsISO8601()
  from?: string;

  @ApiPropertyOptional({
    description: 'ISO 8601 date. Defaults to now.',
  })
  @IsOptional()
  @IsISO8601()
  to?: string;
}

export class AdminAnalyticsRangeDto {
  @ApiProperty()
  from: Date;

  @ApiProperty()
  to: Date;
}

export class AdminAnalyticsByEventDto {
  @ApiProperty({ enum: AnalyticsEventName, enumName: 'AnalyticsEventName' })
  eventName: AnalyticsEventName;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminAnalyticsByDayDto {
  @ApiProperty({ description: 'YYYY-MM-DD in UTC' })
  day: string;

  @ApiProperty({ enum: AnalyticsEventName, enumName: 'AnalyticsEventName' })
  eventName: AnalyticsEventName;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminAnalyticsByPlatformDto {
  @ApiProperty({
    description: 'Platform identifier: ios, android, web, or unknown.',
  })
  platform: string;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminAnalyticsSummaryDto {
  @ApiProperty({ type: AdminAnalyticsRangeDto })
  range: AdminAnalyticsRangeDto;

  @ApiProperty({ type: 'integer' })
  totalEvents: number;

  @ApiProperty({
    type: 'integer',
    description: 'Distinct userId across the window (excludes anonymous).',
  })
  totalUsers: number;

  @ApiProperty({ type: [AdminAnalyticsByEventDto] })
  byEventName: AdminAnalyticsByEventDto[];

  @ApiProperty({ type: [AdminAnalyticsByDayDto] })
  byDay: AdminAnalyticsByDayDto[];

  @ApiProperty({
    type: [AdminAnalyticsByPlatformDto],
    description:
      'Total events grouped by platform for the window. Includes unknown bucket for events with no session.',
  })
  byPlatform: AdminAnalyticsByPlatformDto[];
}
