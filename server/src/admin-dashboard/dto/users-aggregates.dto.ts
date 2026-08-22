import { ApiProperty } from '@nestjs/swagger';
import { AuthProvider, SubscriptionStatus } from '@prisma/client';
import { IsISO8601, IsOptional } from 'class-validator';

export class AdminUsersAggregatesQueryDto {
  @ApiProperty({
    required: false,
    description: 'ISO 8601 date. Defaults to 30 days before `to`.',
  })
  @IsOptional()
  @IsISO8601()
  from?: string;

  @ApiProperty({
    required: false,
    description: 'ISO 8601 date. Defaults to now.',
  })
  @IsOptional()
  @IsISO8601()
  to?: string;
}

export class AdminCountByDayDto {
  @ApiProperty({ description: 'YYYY-MM-DD in UTC' })
  day: string;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminCountByAuthProviderDto {
  @ApiProperty({ enum: AuthProvider, enumName: 'AuthProvider' })
  provider: AuthProvider;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminCountBySubscriptionStatusDto {
  @ApiProperty({ enum: SubscriptionStatus, enumName: 'SubscriptionStatus' })
  status: SubscriptionStatus;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminCountBySubscriptionProductDto {
  @ApiProperty({
    description:
      'Product ID — iOS App Store or Google Play SKU, or "none" for users without an active product.',
  })
  productId: string;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminTopActiveUserDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  email: string;

  @ApiProperty()
  displayName: string;

  @ApiProperty({ type: 'integer' })
  eventCount: number;
}

export class AdminUsersAggregatesDto {
  @ApiProperty({ type: 'integer' })
  totalUsers: number;

  @ApiProperty({ type: [AdminCountByDayDto] })
  signupsByDay: AdminCountByDayDto[];

  @ApiProperty({ type: [AdminCountByAuthProviderDto] })
  byAuthProvider: AdminCountByAuthProviderDto[];

  @ApiProperty({ type: [AdminCountBySubscriptionStatusDto] })
  bySubscriptionStatus: AdminCountBySubscriptionStatusDto[];

  @ApiProperty({ type: [AdminCountBySubscriptionProductDto] })
  bySubscriptionProduct: AdminCountBySubscriptionProductDto[];

  @ApiProperty({
    type: 'integer',
    description:
      'Distinct users with either an active auto-renewable sub or a non-revoked pay_once purchase.',
  })
  activeSubscriptions: number;

  @ApiProperty({
    type: 'integer',
    description:
      'Distinct users with at least one non-revoked pay_once SubscriptionTransaction.',
  })
  activePayOnce: number;

  @ApiProperty({ type: [AdminCountByDayDto] })
  newSubsByDay: AdminCountByDayDto[];

  @ApiProperty({ type: [AdminCountByDayDto] })
  churnByDay: AdminCountByDayDto[];

  @ApiProperty({ type: [AdminTopActiveUserDto] })
  topActiveUsers: AdminTopActiveUserDto[];
}
