import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { SubscriptionStatus } from '@prisma/client';

/**
 * Resolved subscription tier. Mirrors the iOS `StoreManager.SubscriptionTier`
 * raw values and the server `VideoExtractionQuotaService` quota tiers so the
 * Android client can render tier-specific messaging and gating at iOS parity.
 */
export enum SubscriptionTier {
  FREE = 'free',
  PRO_WEEKLY = 'pro_weekly',
  PRO_MONTHLY = 'pro_monthly',
  PRO_YEARLY = 'pro_yearly',
  PAY_ONCE = 'pay_once',
}

export class SubscriptionStatusDto {
  @ApiProperty({
    enum: SubscriptionStatus,
    description: 'Current subscription status',
  })
  status: SubscriptionStatus;

  @ApiProperty({
    enum: SubscriptionTier,
    description:
      'Resolved subscription tier (pay_once outranks subscription SKUs)',
    example: SubscriptionTier.FREE,
  })
  tier: SubscriptionTier;

  @ApiPropertyOptional({
    description: 'Product ID of the active subscription',
    example: 'com.oneplan.subscription.monthly',
  })
  productId: string | null;

  @ApiPropertyOptional({
    description: 'ISO 8601 expiration date of the subscription',
    example: '2026-05-12T00:00:00.000Z',
  })
  expiresAt: string | null;

  @ApiProperty({
    description: 'Whether auto-renewal is enabled',
  })
  autoRenewEnabled: boolean;

  @ApiPropertyOptional({
    description: 'ISO 8601 grace period expiration date (if in grace period)',
    example: '2026-04-15T00:00:00.000Z',
  })
  gracePeriodExpiresAt: string | null;
}
