import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  ActivityAction,
  Currency,
  ExpenseCategory,
  InviteStatus,
  MarketplaceListingStatus,
  PlanScope,
  TripStatus,
} from '@prisma/client';

export class AdminTripUserRefDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  email: string;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional({ nullable: true, type: String })
  avatarUrl: string | null;
}

export class AdminTripListingRefDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  publicId: string;

  @ApiProperty()
  name: string;

  @ApiProperty({
    enum: MarketplaceListingStatus,
    enumName: 'MarketplaceListingStatus',
  })
  status: MarketplaceListingStatus;
}

export class AdminTripCountsDto {
  @ApiProperty({ type: 'integer' })
  members: number;

  @ApiProperty({ type: 'integer' })
  expenses: number;

  @ApiProperty({ type: 'integer' })
  budgets: number;

  @ApiProperty({ type: 'integer' })
  planItems: number;

  @ApiProperty({ type: 'integer' })
  photos: number;

  @ApiProperty({ type: 'integer' })
  notes: number;

  @ApiProperty({ type: 'integer' })
  chatMessages: number;

  @ApiProperty({ type: 'integer' })
  activities: number;
}

export class AdminTripCoreDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  name: string;

  @ApiProperty({ enum: TripStatus, enumName: 'TripStatus' })
  status: TripStatus;

  @ApiPropertyOptional({ nullable: true, type: String })
  coverImageUrl: string | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  inviteCode: string | null;

  @ApiProperty({ enum: Currency, enumName: 'Currency' })
  currency: Currency;

  @ApiProperty({ enum: Currency, enumName: 'Currency', isArray: true })
  localCurrencies: Currency[];

  @ApiPropertyOptional({ nullable: true, type: Date })
  startDate: Date | null;

  @ApiPropertyOptional({ nullable: true, type: Date })
  endDate: Date | null;

  @ApiProperty()
  createdAt: Date;

  @ApiProperty()
  updatedAt: Date;

  @ApiProperty({ type: AdminTripUserRefDto })
  creator: AdminTripUserRefDto;

  @ApiPropertyOptional({ nullable: true, type: String })
  cityName: string | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  stateName: string | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  countryName: string | null;

  @ApiPropertyOptional({ nullable: true, type: AdminTripListingRefDto })
  marketplaceListing: AdminTripListingRefDto | null;

  @ApiProperty({ type: AdminTripCountsDto })
  counts: AdminTripCountsDto;
}

export class AdminTripMemberDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  email: string;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional({ nullable: true, type: String })
  avatarUrl: string | null;

  @ApiProperty({ enum: InviteStatus, enumName: 'InviteStatus' })
  inviteStatus: InviteStatus;

  @ApiPropertyOptional({ nullable: true, type: Date })
  joinedAt: Date | null;
}

export class AdminTripExpenseDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  name: string;

  @ApiPropertyOptional({ nullable: true, type: String })
  note: string | null;

  @ApiProperty()
  amount: number;

  @ApiPropertyOptional({
    nullable: true,
    enum: Currency,
    enumName: 'Currency',
  })
  originalCurrency: Currency | null;

  @ApiProperty({ enum: ExpenseCategory, enumName: 'ExpenseCategory' })
  category: ExpenseCategory;

  @ApiPropertyOptional({ nullable: true, type: AdminTripUserRefDto })
  paidBy: AdminTripUserRefDto | null;

  @ApiProperty()
  expenseDate: Date;

  @ApiProperty({ type: 'integer' })
  shareCount: number;
}

export class AdminTripBudgetDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  name: string;

  @ApiProperty()
  amount: number;

  @ApiPropertyOptional({ nullable: true, type: Number })
  perPersonAmount: number | null;

  @ApiProperty({ enum: PlanScope, enumName: 'PlanScope' })
  scope: PlanScope;

  @ApiPropertyOptional({ nullable: true, type: Number })
  originalAmount: number | null;

  @ApiPropertyOptional({
    nullable: true,
    enum: Currency,
    enumName: 'Currency',
  })
  originalCurrency: Currency | null;
}

export class AdminTripPlanItemDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  title: string;

  @ApiPropertyOptional({ nullable: true, type: String })
  description: string | null;

  @ApiPropertyOptional({ nullable: true, type: Date })
  planDate: Date | null;

  @ApiPropertyOptional({ nullable: true, type: 'integer' })
  dayNumber: number | null;

  @ApiPropertyOptional({
    nullable: true,
    type: String,
    description: 'HH:mm',
  })
  startTime: string | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  location: string | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  address: string | null;

  @ApiPropertyOptional({
    nullable: true,
    enum: ExpenseCategory,
    enumName: 'ExpenseCategory',
  })
  category: ExpenseCategory | null;
}

export class AdminTripPhotoDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  photoUrl: string;

  @ApiPropertyOptional({ nullable: true, type: String })
  caption: string | null;

  @ApiProperty({ type: AdminTripUserRefDto })
  uploadedBy: AdminTripUserRefDto;

  @ApiProperty()
  createdAt: Date;
}

export class AdminTripNoteDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  title: string;

  @ApiPropertyOptional({ nullable: true, type: String })
  body: string | null;

  @ApiProperty()
  isDone: boolean;

  @ApiProperty({ type: AdminTripUserRefDto })
  createdBy: AdminTripUserRefDto;

  @ApiProperty()
  updatedAt: Date;
}

export class AdminTripActivityDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ enum: ActivityAction, enumName: 'ActivityAction' })
  action: ActivityAction;

  @ApiPropertyOptional({ nullable: true, type: AdminTripUserRefDto })
  user: AdminTripUserRefDto | null;

  @ApiProperty()
  createdAt: Date;
}

export class AdminTripDetailDto {
  @ApiProperty({ type: AdminTripCoreDto })
  trip: AdminTripCoreDto;

  @ApiProperty({ type: [AdminTripMemberDto] })
  members: AdminTripMemberDto[];

  @ApiProperty({ type: [AdminTripExpenseDto] })
  expenses: AdminTripExpenseDto[];

  @ApiProperty({ type: [AdminTripBudgetDto] })
  budgets: AdminTripBudgetDto[];

  @ApiProperty({ type: [AdminTripPlanItemDto] })
  planItems: AdminTripPlanItemDto[];

  @ApiProperty({ type: [AdminTripPhotoDto] })
  photos: AdminTripPhotoDto[];

  @ApiProperty({ type: [AdminTripNoteDto] })
  notes: AdminTripNoteDto[];

  @ApiProperty({ type: [AdminTripActivityDto] })
  activities: AdminTripActivityDto[];
}
