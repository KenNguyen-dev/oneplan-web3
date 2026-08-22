import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  Min,
} from 'class-validator';

/**
 * Google Play purchase payload sent by the Android client after a Play Billing
 * purchase or restore. Mirrors the Android `SubscriptionPurchasePayload` and
 * the marketplace `PurchaseMarketplaceListingDto` shape for consistency.
 */
export class VerifyPlayPurchaseDto {
  @ApiProperty({
    description: 'Android application package name used for the purchase',
    example: 'com.oneplan.app',
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(255)
  packageName: string;

  @ApiProperty({
    description:
      'Google Play product identifier (pro_weekly | pro_monthly | pro_yearly | pay_once)',
    example: 'pro_yearly',
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(255)
  productId: string;

  @ApiProperty({
    description: 'Google Play purchase token returned by BillingClient',
    example: 'purchase-token',
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(1024)
  purchaseToken: string;

  @ApiPropertyOptional({
    description: 'Client-observed Google Play order ID, if already available',
    example: 'GPA.1234-5678-9012-34567',
  })
  @IsOptional()
  @IsString()
  @MaxLength(255)
  orderId?: string;

  @ApiPropertyOptional({
    description: 'Client-observed purchase time in Unix epoch milliseconds',
    example: '1711627200000',
  })
  @IsOptional()
  @IsString()
  @MaxLength(32)
  purchaseTimeMillis?: string;

  @ApiPropertyOptional({
    description: 'Client-observed Google Play purchase state (0 = purchased)',
    example: 0,
  })
  @IsOptional()
  @IsInt()
  @Min(0)
  purchaseState?: number;
}
