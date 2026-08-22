import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { InviteStatus, TripStatus } from '@prisma/client';
import { AdminAnalyticsEventDto } from './analytics-event-list.dto';
import { AdminUserSummaryDto } from './user-list.dto';

export class AdminUserTripDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  name: string;

  @ApiProperty({ enum: TripStatus, enumName: 'TripStatus' })
  status: TripStatus;

  @ApiProperty({ enum: InviteStatus, enumName: 'InviteStatus' })
  inviteStatus: InviteStatus;

  @ApiPropertyOptional({ nullable: true, type: Date })
  joinedAt: Date | null;
}

export class AdminUserSubscriptionTxnDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  productId: string;

  @ApiProperty()
  transactionId: string;

  @ApiProperty()
  originalTransactionId: string;

  @ApiProperty({
    description:
      'Derived platform: "apple" when transactionId is numeric (App Store), "android" for Google Play purchase tokens.',
  })
  platform: string;

  @ApiProperty()
  purchaseDate: Date;

  @ApiPropertyOptional({ nullable: true, type: Date })
  expiresDate: Date | null;

  @ApiPropertyOptional({ nullable: true, type: Date })
  revocationDate: Date | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  notificationType: string | null;

  @ApiPropertyOptional({
    nullable: true,
    type: String,
    description:
      'Apple App Store environment (Sandbox / Production). Null for Google Play transactions.',
  })
  environment: string | null;
}

export class AdminUserScanGrantDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  source: string;

  @ApiPropertyOptional({ nullable: true, type: String })
  productId: string | null;

  @ApiProperty({ type: 'integer' })
  amount: number;

  @ApiProperty({ type: 'integer' })
  remaining: number;

  @ApiProperty()
  grantedAt: Date;

  @ApiPropertyOptional({ nullable: true, type: Date })
  expiresAt: Date | null;

  @ApiPropertyOptional({ nullable: true, type: Date })
  revokedAt: Date | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  externalRef: string | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  periodKey: string | null;
}

export class AdminUserScanConsumptionDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  grantId: number;

  @ApiProperty()
  sessionId: string;

  @ApiProperty({ type: 'integer' })
  amount: number;

  @ApiProperty()
  consumedAt: Date;

  @ApiPropertyOptional({ nullable: true, type: Date })
  refundedAt: Date | null;
}

export class AdminUserDetailDto {
  @ApiProperty({ type: AdminUserSummaryDto })
  user: AdminUserSummaryDto;

  @ApiProperty({ type: [AdminUserTripDto] })
  trips: AdminUserTripDto[];

  @ApiProperty({ type: [AdminUserSubscriptionTxnDto] })
  subscriptionHistory: AdminUserSubscriptionTxnDto[];

  @ApiProperty({ type: [AdminUserScanGrantDto] })
  scanCreditGrants: AdminUserScanGrantDto[];

  @ApiProperty({ type: [AdminUserScanConsumptionDto] })
  scanCreditConsumptions: AdminUserScanConsumptionDto[];

  @ApiProperty({ type: [AdminAnalyticsEventDto] })
  recentEvents: AdminAnalyticsEventDto[];
}
