import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class ExtractedPinDto {
  @ApiProperty({
    type: 'integer',
    description: '0-based index within the extraction',
  })
  index: number;

  @ApiProperty({ maxLength: 255 })
  name: string;

  @ApiPropertyOptional({ maxLength: 500 })
  address?: string;

  @ApiPropertyOptional({ type: 'number', minimum: -90, maximum: 90 })
  latitude?: number;

  @ApiPropertyOptional({ type: 'number', minimum: -180, maximum: 180 })
  longitude?: number;

  @ApiPropertyOptional({ maxLength: 1000 })
  notes?: string;

  @ApiPropertyOptional({
    type: 'number',
    description:
      'Seconds into the source video where this location first appears',
  })
  sourceTimestampSec?: number;

  @ApiPropertyOptional({
    maxLength: 120,
    description: 'City the venue is in, as inferred by the model',
  })
  city?: string;

  @ApiPropertyOptional({
    maxLength: 120,
    description: 'Country the venue is in, as inferred by the model',
  })
  country?: string;

  @ApiPropertyOptional({
    description:
      'Coarse category emitted by the model. See the Gemini response schema for the allowed values.',
    maxLength: 32,
  })
  category?: string;

  @ApiPropertyOptional({
    type: 'integer',
    minimum: 1,
    description:
      'Itinerary day this pin belongs to when the video explicitly labels days ("Day 1")',
  })
  dayNumber?: number;

  @ApiPropertyOptional({
    maxLength: 64,
    description:
      'Verbatim time-of-day mention tied to this pin ("9am", "morning")',
  })
  timeOfDayText?: string;
}

export class PinExtractionVideoMetaDto {
  @ApiPropertyOptional()
  title?: string;

  @ApiPropertyOptional()
  description?: string;

  @ApiPropertyOptional()
  uploader?: string;

  @ApiPropertyOptional()
  thumbnail?: string;
}

export enum PinExtractionSessionStatus {
  QUEUED = 'QUEUED',
  RUNNING = 'RUNNING',
  DONE = 'DONE',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED',
}

export class PinExtractionSessionDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  sourceUrl: string;

  @ApiProperty({
    enum: PinExtractionSessionStatus,
    enumName: 'PinExtractionSessionStatus',
  })
  status: PinExtractionSessionStatus;

  @ApiPropertyOptional({
    description: 'Last phase emitted while running. Null on terminal sessions.',
  })
  phase?: string;

  @ApiPropertyOptional({ type: PinExtractionVideoMetaDto })
  videoMeta?: PinExtractionVideoMetaDto;

  @ApiProperty({ type: [ExtractedPinDto] })
  pins: ExtractedPinDto[];

  @ApiProperty({ type: 'integer' })
  pinCount: number;

  @ApiProperty()
  fromCache: boolean;

  @ApiPropertyOptional()
  errorCode?: string;

  @ApiPropertyOptional()
  errorMessage?: string;

  @ApiProperty()
  createdAt: string;

  @ApiPropertyOptional()
  completedAt?: string;
}

// Envelope for GET /board/pins/extract/active. We can't just type the
// response as `PinExtractionSessionDto | null` because OpenAPI 3.0 + the
// Swift generator render that as a non-optional struct — a literal `null`
// body then fails decoding. Wrapping in an envelope makes the nullability
// explicit: callers read `.session` which is naturally optional.
export class ActivePinExtractionResponseDto {
  @ApiPropertyOptional({ type: PinExtractionSessionDto })
  session?: PinExtractionSessionDto;
}
