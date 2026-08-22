import { ApiPropertyOptional } from '@nestjs/swagger';
import { ListingTag } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';
import { MarketplaceFeedTab } from './marketplace-feed-tab.enum';
import { SortDirection } from './sort-direction.enum';

export class ListMarketplaceFeedQueryDto {
  @ApiPropertyOptional({
    description: 'Number of feed items to return (default 20, max 50)',
    type: 'integer',
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  take?: number;

  @ApiPropertyOptional({
    enum: MarketplaceFeedTab,
    default: MarketplaceFeedTab.TRENDING,
  })
  @IsOptional()
  @IsEnum(MarketplaceFeedTab)
  tab?: MarketplaceFeedTab;

  @ApiPropertyOptional({ type: 'integer' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  cityId?: number;

  @ApiPropertyOptional({ type: 'integer' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  stateId?: number;

  @ApiPropertyOptional({ type: 'integer' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  countryId?: number;

  @ApiPropertyOptional({ type: 'integer' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  durationMinDays?: number;

  @ApiPropertyOptional({ type: 'integer' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  durationMaxDays?: number;

  @ApiPropertyOptional({ enum: ListingTag })
  @IsOptional()
  @IsEnum(ListingTag)
  tag?: ListingTag;

  @ApiPropertyOptional({ enum: SortDirection })
  @IsOptional()
  @IsEnum(SortDirection)
  budgetSort?: SortDirection;
}
