import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ExpenseCategory } from '@prisma/client';

export class MarketItemDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  listingId: number;

  @ApiProperty({ type: 'integer' })
  dayNumber: number;

  @ApiProperty()
  title: string;

  @ApiPropertyOptional()
  description: string | null;

  @ApiPropertyOptional()
  location: string | null;

  @ApiPropertyOptional({ type: 'number' })
  latitude: number | null;

  @ApiPropertyOptional({ type: 'number' })
  longitude: number | null;

  @ApiPropertyOptional()
  address: string | null;

  @ApiPropertyOptional({ description: 'HH:MM format' })
  startTime: string | null;

  @ApiPropertyOptional({ enum: ExpenseCategory, enumName: 'ExpenseCategory' })
  category: ExpenseCategory | null;

  @ApiProperty({ type: [String] })
  imageUrls: string[];

  @ApiProperty({ type: 'integer' })
  sortOrder: number;

  @ApiProperty()
  createdAt: string;
}
