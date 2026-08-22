import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class MarketplaceAppliedStatusDto {
  @ApiProperty()
  applied: boolean;

  @ApiPropertyOptional({ type: 'integer', nullable: true })
  acquisitionId: number | null;

  @ApiPropertyOptional({ type: 'string', nullable: true })
  acquiredAt: string | null;
}
