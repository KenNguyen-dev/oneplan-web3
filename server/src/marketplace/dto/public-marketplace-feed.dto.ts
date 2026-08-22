import { ApiProperty, OmitType } from '@nestjs/swagger';
import { MarketplaceFeedItemDto } from './marketplace-feed-item.dto';
import { MarketplaceFeedMatchedScope } from './marketplace-feed-matched-scope.enum';
import { MarketItemDto } from './market-item.dto';

export class PublicMarketplaceFeedItemDto extends OmitType(
  MarketplaceFeedItemDto,
  ['acquired'] as const,
) {
  @ApiProperty({
    type: [MarketItemDto],
    description: 'First 3 plan items of the listing (dayNumber, sortOrder)',
  })
  items: MarketItemDto[];
}

export class PublicMarketplaceFeedDto {
  @ApiProperty({ type: [PublicMarketplaceFeedItemDto] })
  items: PublicMarketplaceFeedItemDto[];

  @ApiProperty({
    type: [PublicMarketplaceFeedItemDto],
    description:
      'Admin-curated featured listings in admin-chosen order. Independent of destination/tag filters; empty when no listing is featured.',
  })
  featured: PublicMarketplaceFeedItemDto[];

  @ApiProperty({ type: [String] })
  destinationNames: string[];

  @ApiProperty({
    enum: MarketplaceFeedMatchedScope,
    nullable: true,
    description:
      'Which destination scope matched after the city → state → country cascade. null when no destination filter was sent; NONE when every cascade level returned zero listings.',
  })
  matchedDestinationScope: MarketplaceFeedMatchedScope | null;
}
