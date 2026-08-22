import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class ScanCreditBalanceDto {
  @ApiProperty({
    type: 'integer',
    description: 'Total scan credits the user can spend right now.',
  })
  available: number;

  @ApiPropertyOptional({
    type: String,
    nullable: true,
    description:
      "ISO 8601 server-time timestamp of the next Pro renewal, when the next billing cycle's scan credits are granted. Null when the user has no active Pro subscription.",
  })
  nextProGrantAt: string | null;
}

// Error body returned with HTTP 402 when a scan would consume a credit the
// user does not have. Keeps overlapping fields with the old quota error so
// the iOS decoder change stays minimal.
export class InsufficientScanCreditsErrorDto {
  @ApiProperty({ example: 'insufficient_scan_credits' })
  code: string;

  @ApiProperty()
  message: string;

  @ApiProperty({ type: 'integer' })
  available: number;

  @ApiPropertyOptional({ type: String, nullable: true })
  nextProGrantAt: string | null;

  @ApiProperty({
    description: 'Whether the client should offer the buy-credits flow.',
  })
  canPurchase: boolean;
}
