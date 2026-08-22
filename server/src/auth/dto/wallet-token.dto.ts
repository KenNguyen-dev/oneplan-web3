import { ApiProperty } from '@nestjs/swagger';

export class WalletTokenDto {
  @ApiProperty({
    description:
      'RS256 JWT identifying the caller to the wallet provider. Valid for ' +
      'five minutes and useful for nothing else.',
  })
  token: string;
}
