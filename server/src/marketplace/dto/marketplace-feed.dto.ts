import { ApiProperty } from '@nestjs/swagger';
import { MarketplaceFeedItemDto } from './marketplace-feed-item.dto';
import { MarketplaceFeedMatchedScope } from './marketplace-feed-matched-scope.enum';

export class MarketplaceFeedDto {
  @ApiProperty({ type: [MarketplaceFeedItemDto] })
  items: MarketplaceFeedItemDto[];

  @ApiProperty({
    type: [MarketplaceFeedItemDto],
    description:
      'Admin-curated featured listings in admin-chosen order. Independent of destination/tag filters; empty when no listing is featured.',
  })
  featured: MarketplaceFeedItemDto[];

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
