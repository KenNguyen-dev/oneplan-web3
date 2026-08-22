import { ApiProperty } from '@nestjs/swagger';
import { MarketplaceListingDto } from './marketplace-listing.dto';

export class CreatorProfileDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  displayName: string;

  @ApiProperty({ nullable: true })
  avatarUrl: string | null;

  createdAt: string;

  @ApiProperty({ type: [MarketplaceListingDto] })
  listings: MarketplaceListingDto[];
}
