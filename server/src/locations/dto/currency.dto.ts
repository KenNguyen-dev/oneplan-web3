import { ApiProperty } from '@nestjs/swagger';
import { Currency } from '@prisma/client';

export class CurrencyDto {
  @ApiProperty({
    enum: Currency,
    enumName: 'Currency',
    description: 'Currency code (e.g. VND, USD)',
  })
  code: Currency;

  @ApiProperty({ description: 'Human-readable name (e.g. Vietnamese Dong)' })
  name: string;

  @ApiProperty({ description: 'Currency symbol (e.g. đ, $)' })
  symbol: string;

  @ApiProperty({
    type: 'integer',
    example: 2,
    description: 'Number of fractional digits normally used for this currency',
  })
  decimalPlaces: number;
}
