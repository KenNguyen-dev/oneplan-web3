import { ApiProperty } from '@nestjs/swagger';

export class ScanReceiptDto {
  @ApiProperty({
    type: 'string',
    format: 'binary',
    description: 'Receipt image file (JPEG/PNG)',
  })
  image: any;
}
