import { ApiProperty } from '@nestjs/swagger';
import { MarketplaceAcquisitionSummaryDto } from './marketplace-acquisition-summary.dto';
import { AcquisitionItemDto } from './acquisition-item.dto';

export class MarketplaceAcquisitionDetailDto extends MarketplaceAcquisitionSummaryDto {
  @ApiProperty({ type: [AcquisitionItemDto] })
  items: AcquisitionItemDto[];
}
