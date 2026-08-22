import { ApiProperty } from '@nestjs/swagger';
import { IsString, Length } from 'class-validator';

export class LinkWalletDto {
  @ApiProperty({
    description: 'Base58 Solana public key of the embedded wallet',
  })
  @IsString()
  @Length(32, 44)
  publicKey: string;
}

export class LinkWalletResponseDto {
  @ApiProperty()
  publicKey: string;
}
