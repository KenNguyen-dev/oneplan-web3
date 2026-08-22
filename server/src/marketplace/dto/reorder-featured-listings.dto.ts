import { ApiProperty } from '@nestjs/swagger';
import { ArrayUnique, IsArray, IsInt } from 'class-validator';

export class ReorderFeaturedListingsDto {
  @ApiProperty({
    type: [Number],
    description:
      'Every currently featured listing id, in the desired display order. Must match the featured set exactly.',
  })
  @IsArray()
  @IsInt({ each: true })
  @ArrayUnique()
  listingIds: number[];
}
