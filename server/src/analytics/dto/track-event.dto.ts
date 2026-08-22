import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsDateString, IsEnum, IsObject, IsOptional } from 'class-validator';
import { AnalyticsEventName } from '../constants/events';

export class TrackEventDto {
  @ApiProperty({ enum: AnalyticsEventName })
  @IsEnum(AnalyticsEventName)
  eventName: AnalyticsEventName;

  @ApiProperty({ description: 'ISO8601 client timestamp when event occurred' })
  @IsDateString()
  occurredAt: string;

  @ApiPropertyOptional({ type: 'object', additionalProperties: true })
  @IsOptional()
  @IsObject()
  properties?: Record<string, unknown>;
}
