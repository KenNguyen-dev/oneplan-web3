import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsEmail,
  IsEnum,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export enum SocialProvider {
  APPLE = 'APPLE',
  GOOGLE = 'GOOGLE',
}

export class SocialLoginDto {
  /** The identity token from Apple or Google */
  @ApiProperty()
  @IsString()
  identityToken: string;

  @ApiProperty({ enum: SocialProvider })
  @IsEnum(SocialProvider)
  provider: SocialProvider;

  /** Optional display name (used if creating a new user) */
  @ApiPropertyOptional({ maxLength: 100 })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  displayName?: string;

  /** Optional email (used when Apple doesn't include email after first auth) */
  @ApiPropertyOptional({ example: 'user@example.com' })
  @IsOptional()
  @IsEmail()
  email?: string;

  /**
   * Raw nonce for replay protection (Apple flow). The client generates a
   * cryptographically random value, sets `request.nonce = sha256Hex(raw)` on
   * the Apple authorization request, and forwards the raw value here. The
   * server verifies sha256(raw) matches the `nonce` claim in Apple's JWT.
   */
  @ApiPropertyOptional({
    description: 'Raw nonce for Apple Sign-In replay protection',
  })
  @IsOptional()
  @IsString()
  @MaxLength(128)
  nonce?: string;
}
