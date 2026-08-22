import { ApiProperty } from '@nestjs/swagger';
import { Currency, ExpenseCategory, TripStatus } from '@prisma/client';
import { IsISO8601, IsOptional } from 'class-validator';
import { AdminCountByDayDto } from './users-aggregates.dto';

export class AdminTripsAggregatesQueryDto {
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

export class AdminCountByTripStatusDto {
  @ApiProperty({ enum: TripStatus, enumName: 'TripStatus' })
  status: TripStatus;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminCountByCurrencyDto {
  @ApiProperty({ enum: Currency, enumName: 'Currency' })
  currency: Currency;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminTripSizeBucketDto {
  @ApiProperty({ description: 'Member-count bucket label, e.g. "1", "2-3".' })
  bucket: string;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminExpenseTotalByCurrencyDto {
  @ApiProperty({ enum: Currency, enumName: 'Currency' })
  currency: Currency;

  @ApiProperty({
    type: 'number',
    description: 'Summed expense amount in this trip-base currency.',
  })
  total: number;
}

export class AdminTopDestinationDto {
  @ApiProperty({ description: 'City or country name.' })
  name: string;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminTripFeatureAdoptionDto {
  @ApiProperty({ description: 'Feature key, e.g. "photos", "chat".' })
  feature: string;

  @ApiProperty({ type: 'integer', description: 'Trips with at least one.' })
  tripCount: number;

  @ApiProperty({ type: 'number', description: 'Average count per trip.' })
  avgPerTrip: number;
}

export class AdminExpenseCountByCategoryDto {
  @ApiProperty({ enum: ExpenseCategory, enumName: 'ExpenseCategory' })
  category: ExpenseCategory;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminCountByMonthDto {
  @ApiProperty({ description: 'YYYY-MM in UTC' })
  month: string;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminTopCreatorDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  email: string;

  @ApiProperty()
  displayName: string;

  @ApiProperty({ type: 'integer' })
  tripCount: number;
}

export class AdminCountByNameDto {
  @ApiProperty()
  name: string;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class AdminTripsAggregatesDto {
  @ApiProperty({ type: 'integer', description: 'All-time trip count.' })
  totalTrips: number;

  @ApiProperty({ type: 'integer', description: 'Trips created in the window.' })
  tripsInWindow: number;

  @ApiProperty({ type: [AdminCountByDayDto] })
  tripsByDay: AdminCountByDayDto[];

  @ApiProperty({ type: [AdminCountByTripStatusDto] })
  byStatus: AdminCountByTripStatusDto[];

  @ApiProperty({
    type: 'number',
    description: 'Average accepted+pending members per trip (all-time).',
  })
  avgMembersPerTrip: number;

  @ApiProperty({ type: [AdminTripSizeBucketDto] })
  tripSizeBuckets: AdminTripSizeBucketDto[];

  @ApiProperty({
    type: 'number',
    description: 'Accepted invites / total invites, 0–1 (all-time).',
  })
  inviteAcceptanceRate: number;

  @ApiProperty({
    type: 'number',
    description: 'Average number of expense rows per trip (all-time).',
  })
  avgExpensesPerTrip: number;

  @ApiProperty({ type: 'integer' })
  tripsWithExpenses: number;

  @ApiProperty({
    type: [AdminExpenseTotalByCurrencyDto],
    description:
      'Expense totals grouped by trip base currency (not summed across currencies).',
  })
  expenseTotalsByCurrency: AdminExpenseTotalByCurrencyDto[];

  @ApiProperty({
    type: [AdminCountByCurrencyDto],
    description: 'Trip base-currency mix.',
  })
  byCurrency: AdminCountByCurrencyDto[];

  @ApiProperty({ type: [AdminTopDestinationDto] })
  topDestinations: AdminTopDestinationDto[];

  @ApiProperty({
    type: 'integer',
    description:
      'Trips created in the equal-length window immediately before [from,to].',
  })
  tripsInWindowPrev: number;

  @ApiProperty({ type: [AdminTripFeatureAdoptionDto] })
  featureAdoption: AdminTripFeatureAdoptionDto[];

  @ApiProperty({ type: [AdminExpenseCountByCategoryDto] })
  expenseByCategory: AdminExpenseCountByCategoryDto[];

  @ApiProperty({
    type: 'number',
    description: 'Average trip length in days (trips with start+end dates).',
  })
  avgDurationDays: number;

  @ApiProperty({ type: [AdminTripSizeBucketDto] })
  durationBuckets: AdminTripSizeBucketDto[];

  @ApiProperty({
    type: 'integer',
    description: 'Trips with a future start date.',
  })
  upcomingTrips: number;

  @ApiProperty({
    type: 'integer',
    description: 'Trips with a past start date.',
  })
  pastTrips: number;

  @ApiProperty({ type: [AdminCountByMonthDto] })
  tripsByMonth: AdminCountByMonthDto[];

  @ApiProperty({
    type: 'integer',
    description: 'Trips created from an acquired marketplace plan.',
  })
  tripsFromMarketplace: number;

  @ApiProperty({ type: [AdminTopCreatorDto] })
  topCreators: AdminTopCreatorDto[];

  @ApiProperty({
    type: 'number',
    description: 'Creators with more than one trip / total creators, 0–1.',
  })
  repeatCreatorRate: number;

  @ApiProperty({ type: 'number' })
  avgTripsPerCreator: number;

  @ApiProperty({ type: [AdminCountByNameDto] })
  topCountries: AdminCountByNameDto[];

  @ApiProperty({ type: [AdminCountByNameDto] })
  byRegion: AdminCountByNameDto[];
}
