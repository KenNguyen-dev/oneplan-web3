import { ApiProperty } from '@nestjs/swagger';
import { Currency } from '@prisma/client';

export class ExchangeRateResponseDto {
  @ApiProperty({ enum: Currency, enumName: 'Currency' })
  from!: Currency;

  @ApiProperty({ enum: Currency, enumName: 'Currency' })
  to!: Currency;

  @ApiProperty({
    type: Number,
    description:
      'Exchange rate: multiply an amount in `from` by this value to get the equivalent amount in `to`.',
    example: 24500.0,
  })
  rate!: number;

  @ApiProperty({
    type: String,
    description:
      'ISO-8601 timestamp of when this rate was last refreshed. Plain string (not `format: date-time`) to match the rest of the API — iOS parses it manually because swift-openapi-generator defaults to a strict `ISO8601DateFormatter` that rejects fractional seconds emitted by Node `Date.toISOString()`.',
  })
  fetchedAt!: string;

  @ApiProperty({
    type: Boolean,
    description:
      'True when the returned rate is older than 24h, from static fallback, or otherwise unreliable.',
  })
  isStale!: boolean;
}
