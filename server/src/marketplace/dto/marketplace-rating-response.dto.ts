import { ApiProperty } from '@nestjs/swagger';

export class MarketplaceRatingResponseDto {
  @ApiProperty()
  userRating: number;

  @ApiProperty({ nullable: true, type: String })
  averageRating: string | null;

  @ApiProperty()
  ratingCount: number;
}
