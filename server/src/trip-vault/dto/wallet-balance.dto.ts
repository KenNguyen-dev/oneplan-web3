import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class WalletBalanceDto {
  @ApiPropertyOptional({
    nullable: true,
    description: 'The caller wallet address, or null before one is linked',
  })
  publicKey: string | null;

  @ApiPropertyOptional({
    nullable: true,
    description: 'Caller USDC ATA in base58, or null before a wallet is linked',
  })
  usdcAta: string | null;

  @ApiProperty({ description: 'USDC held by the caller, in micro-USDC' })
  balanceMicro: string;
}
