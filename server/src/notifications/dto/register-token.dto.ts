import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { EngagementLocale } from '@prisma/client';
import {
  IsEnum,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class RegisterTokenDto {
  @ApiProperty({
    description: 'Push notification device token',
    maxLength: 200,
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  token: string;

  @ApiProperty({
    description: 'Device platform',
    enum: ['ios', 'android'],
    default: 'ios',
    required: false,
  })
  @IsOptional()
  @IsIn(['ios', 'android'])
  platform?: string;

  @ApiPropertyOptional({
    enum: EngagementLocale,
    enumName: 'EngagementLocale',
    description:
      'Device language; persisted to the user so engagement copy is localized.',
  })
  @IsOptional()
  @IsEnum(EngagementLocale)
  locale?: EngagementLocale;
}
