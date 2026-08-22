import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { SocialProvider } from './social-login.dto';

export class LinkAccountDto {
  @ApiProperty()
  @IsString()
  identityToken: string;

  @ApiProperty({ enum: SocialProvider })
  @IsEnum(SocialProvider)
  provider: SocialProvider;

  /** Raw nonce for Apple Sign-In replay protection — see SocialLoginDto. */
  @ApiPropertyOptional({
    description: 'Raw nonce for Apple Sign-In replay protection',
  })
  @IsOptional()
  @IsString()
  @MaxLength(128)
  nonce?: string;
}
