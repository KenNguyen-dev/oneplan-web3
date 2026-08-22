import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

/**
 * Every amount is a decimal string. Micro-USDC exceeds Number.MAX_SAFE_INTEGER
 * at large balances, and JSON numbers would silently lose precision.
 */
export class VaultBalanceDto {
  @ApiProperty({ description: 'Vault PDA in base58' })
  vaultPda: string;

  @ApiProperty({ description: 'Vault USDC ATA in base58' })
  usdcAta: string;

  @ApiProperty({
    description:
      'OnePlan treasury USDC ATA that receives the deposit skim, in base58',
  })
  treasuryAta: string;

  @ApiPropertyOptional({
    description:
      'USDC ATA that receives merchant spends (server receiver wallet), in base58. Absent when the payout receiver is not configured.',
  })
  spendRecipientAta?: string;

  @ApiProperty({ description: 'Balance in micro-USDC, as a decimal string' })
  balanceMicro: string;

  @ApiProperty({ description: 'Single-signature threshold in micro-USDC' })
  thresholdMicro: string;

  @ApiProperty({ description: 'Rolling daily ceiling in micro-USDC' })
  dailyLimitMicro: string;
}
