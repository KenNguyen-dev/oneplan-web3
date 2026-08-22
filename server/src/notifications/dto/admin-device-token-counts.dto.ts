import { ApiProperty } from '@nestjs/swagger';

export class AdminDeviceTokenCountsDto {
  @ApiProperty({
    type: 'integer',
    description: 'iOS device tokens registered.',
  })
  ios: number;

  @ApiProperty({
    type: 'integer',
    description: 'Android device tokens registered.',
  })
  android: number;

  @ApiProperty({ type: 'integer', description: 'Total device tokens.' })
  total: number;
}
