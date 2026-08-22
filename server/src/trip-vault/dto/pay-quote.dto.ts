import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, Matches } from 'class-validator';

export class PayQuoteRequestDto {
  @ApiProperty({
    description: 'Raw EMVCo payload scanned from the VietQR code',
  })
  @IsString()
  qrPayload: string;

  @ApiPropertyOptional({
    description:
      'Amount in VND as a decimal string. Required when the QR carries no amount',
  })
  @IsOptional()
  @Matches(/^\d+$/)
  amountVnd?: string;
}

export class PayQuoteDto {
  @ApiProperty({
    description: 'Account holder name reported by the payout provider',
  })
  recipientName: string;

  @ApiProperty({ description: 'NAPAS bank BIN' })
  bankBin: string;

  @ApiProperty()
  accountNumber: string;

  @ApiProperty({ description: 'Amount in VND as a decimal string' })
  amountVnd: string;

  @ApiProperty({ description: 'Amount in micro-USDC as a decimal string' })
  amountUsdcMicro: string;

  @ApiProperty({
    description: 'Provider fee in micro-USDC as a decimal string',
  })
  feeMicro: string;

  @ApiProperty({ description: 'VND per USDC' })
  rate: string;

  @ApiProperty({ description: 'True when a second member must approve' })
  needsApproval: boolean;
}
