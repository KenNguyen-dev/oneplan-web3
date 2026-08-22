import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Currency, TripStatus } from '@prisma/client';
import { TripLocationDto } from './trip.dto';

export class TripSummaryDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  name: string;

  @ApiPropertyOptional()
  coverImageUrl: string | null;

  @ApiProperty({ enum: TripStatus, enumName: 'TripStatus' })
  status: TripStatus;

  @ApiPropertyOptional()
  startDate: string | null;

  @ApiPropertyOptional()
  endDate: string | null;

  @ApiProperty({ type: 'integer' })
  memberCount: number;

  @ApiPropertyOptional({ type: 'integer', nullable: true })
  lastSeenChatMessageId: number | null;

  @ApiProperty({ enum: Currency, enumName: 'Currency' })
  currency: Currency;

  @ApiPropertyOptional({ type: TripLocationDto })
  location: TripLocationDto | null;
}
