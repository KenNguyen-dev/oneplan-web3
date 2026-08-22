import { ApiProperty } from '@nestjs/swagger';
import {
  IsEmail,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';

const STRONG_PASSWORD_REGEX = /^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{10,128}$/;
const STRONG_PASSWORD_MESSAGE =
  'Password must be 10–128 characters and include uppercase, lowercase, and a digit.';

export class RegisterDto {
  @ApiProperty({ example: 'user@example.com' })
  @IsEmail()
  email: string;

  @ApiProperty({ minLength: 10, maxLength: 128 })
  @IsString()
  @MinLength(10)
  @MaxLength(128)
  @Matches(STRONG_PASSWORD_REGEX, { message: STRONG_PASSWORD_MESSAGE })
  password: string;

  @ApiProperty({ example: 'John Doe', maxLength: 100 })
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  displayName: string;
}
