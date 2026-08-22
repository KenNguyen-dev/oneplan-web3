import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Currency, ListingTag } from '@prisma/client';

export class MarketplaceFeedItemDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  createdById: number;

  @ApiProperty()
  name: string;

  @ApiProperty()
  creatorName: string;

  @ApiProperty({ nullable: true, type: String })
  creatorAvatarUrl: string | null;

  @ApiPropertyOptional()
  coverImageUrl: string | null;

  @ApiProperty({ type: 'string', description: 'Decimal price' })
  price: string;

  @ApiProperty({ enum: Currency, enumName: 'Currency' })
  currency: Currency;

  @ApiProperty({
    enum: ListingTag,
    enumName: 'ListingTag',
    isArray: true,
  })
  tags: ListingTag[];

  @ApiPropertyOptional()
  cityName: string | null;

  @ApiPropertyOptional()
  stateName: string | null;

  @ApiPropertyOptional()
  countryName: string | null;

  @ApiProperty({ type: 'integer' })
  durationDays: number;

  @ApiProperty({ type: 'integer' })
  activityCount: number;

  @ApiProperty({ type: 'integer' })
  appliedCount: number;

  @ApiProperty({ nullable: true, type: String })
  averageRating: string | null;

  @ApiProperty()
  ratingCount: number;

  @ApiProperty()
  acquired: boolean;

  @ApiProperty()
  createdAt: string;
}
