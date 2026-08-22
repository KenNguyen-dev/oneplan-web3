import { ApiProperty } from '@nestjs/swagger';

export class AppAccountTokenDto {
  @ApiProperty({
    description:
      'Stable UUID used to associate App Store purchases with this user',
    format: 'uuid',
  })
  appAccountToken: string;
}
