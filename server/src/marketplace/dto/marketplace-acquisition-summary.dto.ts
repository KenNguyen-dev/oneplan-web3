import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Currency, ListingTag } from '@prisma/client';

export class MarketplaceAcquisitionSummaryDto {
  @ApiProperty({ type: 'integer' })
  acquisitionId: number;

  @ApiPropertyOptional({
    type: 'integer',
    nullable: true,
    description: 'Null if the source listing was hard-deleted',
  })
  listingId: number | null;

  @ApiProperty()
  name: string;

  @ApiPropertyOptional()
  description: string | null;

  @ApiPropertyOptional()
  coverImageUrl: string | null;

  @ApiProperty({
    type: 'string',
    description: 'Decimal price at acquisition time',
  })
  price: string;

  @ApiProperty({ enum: Currency, enumName: 'Currency' })
  currency: Currency;

  @ApiProperty({
    enum: ListingTag,
    enumName: 'ListingTag',
    isArray: true,
  })
  tags: ListingTag[];

  @ApiProperty({ type: 'integer' })
  durationDays: number;

  @ApiProperty({ type: 'integer' })
  activityCount: number;

  @ApiProperty()
  creatorName: string;

  @ApiPropertyOptional({ nullable: true, type: String })
  creatorAvatarUrl: string | null;

  @ApiPropertyOptional({ type: 'integer' })
  cityId: number | null;

  @ApiPropertyOptional({ type: 'integer' })
  stateId: number | null;

  @ApiPropertyOptional({ type: 'integer' })
  countryId: number | null;

  @ApiPropertyOptional()
  cityName: string | null;

  @ApiPropertyOptional()
  stateName: string | null;

  @ApiPropertyOptional()
  countryName: string | null;

  @ApiProperty()
  acquiredAt: string;

  @ApiProperty({
    description:
      'True if the live listing is still publicly available (APPROVED + not deleted)',
  })
  listingStillAvailable: boolean;
}
