import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';

// Auto-renewable Pro packages that can be gifted. pay_once is intentionally
// excluded: its tier resolves from a SubscriptionTransaction row, not from the
// User columns a gift writes, so it cannot be gifted this way.
export enum GiftPackage {
  PRO_WEEKLY = 'pro_weekly',
  PRO_MONTHLY = 'pro_monthly',
  PRO_YEARLY = 'pro_yearly',
}

export class GiftDto {
  @ApiProperty({
    example: 'user@example.com',
    description: "Recipient's email",
  })
  @IsEmail()
  email: string;

  @ApiPropertyOptional({
    type: 'integer',
    minimum: 1,
    maximum: 1000,
    description: 'Number of video scan credits to gift',
  })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(1000)
  scans?: number;

  @ApiPropertyOptional({
    enum: GiftPackage,
    enumName: 'GiftPackage',
    description: 'Pro package to gift (extends any existing Pro time)',
  })
  @IsOptional()
  @IsEnum(GiftPackage)
  package?: GiftPackage;
}

export class GiftResultDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  email: string;

  @ApiProperty({
    type: 'integer',
    description: 'Scan credits granted (0 if none)',
  })
  scansGranted: number;

  @ApiPropertyOptional({
    enum: GiftPackage,
    enumName: 'GiftPackage',
    description: 'Package granted, if any',
    nullable: true,
  })
  packageGranted: GiftPackage | null;

  @ApiPropertyOptional({
    type: 'string',
    nullable: true,
    example: '2026-08-11T00:00:00.000Z',
    description: 'New Pro expiry (ISO string) when a package was gifted',
  })
  subscriptionExpiresAt: string | null;
}

export class GiftLogDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  recipientUserId: number;

  @ApiProperty()
  recipientEmail: string;

  @ApiProperty({ description: 'Admin who sent the gift' })
  adminEmail: string;

  @ApiProperty({ type: 'integer' })
  scans: number;

  @ApiPropertyOptional({ type: 'string', nullable: true })
  package: string | null;

  @ApiPropertyOptional({ type: 'string', nullable: true })
  subscriptionExpiresAt: string | null;

  @ApiProperty({ description: 'ISO timestamp' })
  createdAt: string;
}
