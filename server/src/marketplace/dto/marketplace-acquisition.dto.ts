import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class MarketplaceAcquisitionDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiPropertyOptional({ type: 'integer', nullable: true })
  listingId: number | null;

  @ApiProperty()
  acquiredAt: string;
}
