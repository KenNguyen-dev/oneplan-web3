import { ApiProperty } from '@nestjs/swagger';

export class AuthUserDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  email: string;
  displayName: string;
  avatarUrl: string | null;
}

export class AuthResponseDto {
  accessToken: string;
  refreshToken: string;

  /** Access token expiry in seconds */
  @ApiProperty({ type: 'integer' })
  expiresIn: number;

  user: AuthUserDto;
}
