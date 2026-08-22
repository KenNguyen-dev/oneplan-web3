import { ApiProperty } from '@nestjs/swagger';
import { IsInt } from 'class-validator';

export class FulfillTripRequestDto {
  @ApiProperty({
    type: 'integer',
    description: 'APPROVED marketplace listing that fulfills this request',
  })
  @IsInt()
  listingId: number;
}
