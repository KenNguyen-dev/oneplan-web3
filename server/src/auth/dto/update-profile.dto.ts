import { ApiPropertyOptional } from '@nestjs/swagger';
import { Currency, EngagementLocale } from '@prisma/client';
import {
  IsBoolean,
  IsEnum,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

export class UpdateProfileDto {
  @ApiPropertyOptional({ example: 'John Doe', maxLength: 100 })
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  displayName?: string;

  @ApiPropertyOptional({
    enum: Currency,
    enumName: 'Currency',
    description: 'Preferred currency for new trips',
  })
  @IsOptional()
  @IsEnum(Currency)
  preferredCurrency?: Currency;

  @ApiPropertyOptional({
    enum: EngagementLocale,
    enumName: 'EngagementLocale',
    description: 'Preferred language for engagement notifications (EN/VN)',
  })
  @IsOptional()
  @IsEnum(EngagementLocale)
  locale?: EngagementLocale;

  @ApiPropertyOptional({
    description: 'Opt out (false) / back in (true) of engagement push nudges',
  })
  @IsOptional()
  @IsBoolean()
  engagementPushEnabled?: boolean;

  @ApiPropertyOptional({
    description:
      'Set true to record explicit marketing-push consent (stamps engagementConsentedAt server-side). Required before any engagement push is sent (App Store 4.5.4).',
  })
  @IsOptional()
  @IsBoolean()
  engagementConsent?: boolean;
}
