import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { AuthProvider, SubscriptionStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export enum AdminUserSortBy {
  createdAt = 'createdAt',
  scanCredits = 'scanCredits',
  trips = 'trips',
  subscriptionExpiresAt = 'subscriptionExpiresAt',
}

export enum AdminSortDir {
  asc = 'asc',
  desc = 'desc',
}

export class AdminUserListQueryDto {
  @ApiPropertyOptional({ type: 'integer', minimum: 1, default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({
    type: 'integer',
    minimum: 1,
    maximum: 100,
    default: 25,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 25;

  @ApiPropertyOptional({ description: 'Match against email or display name.' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  search?: string;

  @ApiPropertyOptional({
    enum: AdminUserSortBy,
    enumName: 'AdminUserSortBy',
    default: AdminUserSortBy.createdAt,
  })
  @IsOptional()
  @IsEnum(AdminUserSortBy)
  sortBy?: AdminUserSortBy = AdminUserSortBy.createdAt;

  @ApiPropertyOptional({
    enum: AdminSortDir,
    enumName: 'AdminSortDir',
    default: AdminSortDir.desc,
  })
  @IsOptional()
  @IsEnum(AdminSortDir)
  sortDir?: AdminSortDir = AdminSortDir.desc;
}

export class AdminUserSummaryDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  email: string;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional({ nullable: true, type: String })
  avatarUrl: string | null;

  @ApiProperty()
  createdAt: Date;

  @ApiProperty({
    type: [String],
    enum: AuthProvider,
    enumName: 'AuthProvider',
    isArray: true,
  })
  authProviders: AuthProvider[];

  @ApiProperty({ enum: SubscriptionStatus, enumName: 'SubscriptionStatus' })
  subscriptionStatus: SubscriptionStatus;

  @ApiPropertyOptional({ nullable: true, type: String })
  subscriptionProductId: string | null;

  @ApiPropertyOptional({ nullable: true, type: Date })
  subscriptionExpiresAt: Date | null;

  @ApiProperty({ type: 'integer' })
  scanCreditsRemaining: number;

  @ApiProperty({ type: 'integer' })
  tripCount: number;
}

export class AdminUserListResponseDto {
  @ApiProperty({ type: [AdminUserSummaryDto] })
  items: AdminUserSummaryDto[];

  @ApiProperty({ type: 'integer' })
  total: number;

  @ApiProperty({ type: 'integer' })
  page: number;

  @ApiProperty({ type: 'integer' })
  limit: number;
}
