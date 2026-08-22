import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { AuthProvider, Currency, EngagementLocale } from '@prisma/client';

export class UserProfileDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  email: string;
  displayName: string;
  avatarUrl: string | null;
  createdAt: string;

  @ApiPropertyOptional({ description: 'Unique friend code for QR sharing' })
  friendCode: string | null;

  /** List of linked authentication providers */
  @ApiProperty({ enum: AuthProvider, isArray: true })
  providers: AuthProvider[];

  @ApiProperty({ description: 'Whether user has active Pro subscription' })
  isPro: boolean;

  @ApiProperty({
    enum: Currency,
    enumName: 'Currency',
    description: 'User preferred currency',
  })
  preferredCurrency: Currency;

  @ApiProperty({
    description:
      'Whether the user is recognised as an admin (server-side check against ADMIN_EMAILS).',
  })
  isAdmin: boolean;

  @ApiProperty({
    enum: EngagementLocale,
    enumName: 'EngagementLocale',
    description: 'Preferred language for engagement notifications',
  })
  locale: EngagementLocale;

  @ApiProperty({ description: 'Whether engagement push nudges are enabled' })
  engagementPushEnabled: boolean;

  @ApiProperty({
    description: 'Whether the user has given marketing-push consent',
  })
  engagementConsentGiven: boolean;
}
