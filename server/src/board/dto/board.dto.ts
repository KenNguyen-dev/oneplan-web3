import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class BoardPinDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  boardId: number;

  @ApiProperty({ maxLength: 255 })
  name: string;

  @ApiPropertyOptional({ maxLength: 500 })
  address?: string;

  @ApiPropertyOptional({ type: 'number' })
  latitude?: number;

  @ApiPropertyOptional({ type: 'number' })
  longitude?: number;

  @ApiPropertyOptional({ maxLength: 1000 })
  notes?: string;

  @ApiPropertyOptional({ maxLength: 1000 })
  sourceUrl?: string;

  @ApiPropertyOptional({ type: 'number' })
  sourceTimestampSec?: number;

  @ApiPropertyOptional({ maxLength: 64 })
  category?: string;

  @ApiPropertyOptional({
    type: 'integer',
    minimum: 1,
    description: 'Itinerary day narrated in the source video ("Day 1")',
  })
  dayNumber?: number;

  @ApiPropertyOptional({
    maxLength: 64,
    description: 'Verbatim time-of-day mention from the source video',
  })
  timeOfDayText?: string;

  @ApiProperty({ type: 'integer' })
  sortOrder: number;

  @ApiProperty()
  createdAt: string;
}

export class BoardSummaryDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ maxLength: 255 })
  title: string;

  @ApiPropertyOptional({ maxLength: 500 })
  description?: string;

  @ApiPropertyOptional({ maxLength: 500 })
  coverImageUrl?: string;

  @ApiPropertyOptional({ type: 'integer' })
  cityId?: number;

  @ApiPropertyOptional({ type: 'integer' })
  stateId?: number;

  @ApiPropertyOptional({ type: 'integer' })
  countryId?: number;

  @ApiPropertyOptional()
  locationLabel?: string;

  @ApiProperty({ type: 'integer' })
  pinCount: number;

  @ApiProperty()
  createdAt: string;

  @ApiProperty()
  updatedAt: string;
}

export class BoardDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ maxLength: 255 })
  title: string;

  @ApiPropertyOptional({ maxLength: 500 })
  description?: string;

  @ApiPropertyOptional({ maxLength: 500 })
  coverImageUrl?: string;

  @ApiPropertyOptional({ type: 'integer' })
  cityId?: number;

  @ApiPropertyOptional({ type: 'integer' })
  stateId?: number;

  @ApiPropertyOptional({ type: 'integer' })
  countryId?: number;

  @ApiPropertyOptional()
  locationLabel?: string;

  @ApiProperty({ type: [BoardPinDto] })
  pins: BoardPinDto[];

  @ApiProperty()
  createdAt: string;

  @ApiProperty()
  updatedAt: string;
}
