import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, MaxLength } from 'class-validator';

export class TelegramSettingsDto {
  @ApiProperty({
    description: 'Whether the campaign (CTA + Get Code button) is active.',
  })
  campaignEnabled: boolean;

  @ApiProperty({
    description: 'The greeting sent to each new member. May contain {name}.',
  })
  welcomeText: string;

  @ApiProperty({
    description: 'The campaign call-to-action shown below the greeting.',
  })
  cta: string;
}

export class UpdateTelegramSettingsDto {
  @ApiPropertyOptional({
    description: 'Turn the campaign on/off (CTA + Get Code button).',
  })
  @IsOptional()
  @IsBoolean()
  campaignEnabled?: boolean;

  @ApiPropertyOptional({
    description: 'Override the greeting. Empty string reverts to the default.',
    maxLength: 4096,
  })
  @IsOptional()
  @IsString()
  @MaxLength(4096)
  welcomeText?: string;

  @ApiPropertyOptional({
    description:
      'Override the campaign CTA. Empty string reverts to the default.',
    maxLength: 4096,
  })
  @IsOptional()
  @IsString()
  @MaxLength(4096)
  cta?: string;
}
