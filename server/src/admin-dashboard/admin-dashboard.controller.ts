import { Controller, Get, Param, ParseIntPipe, Query } from '@nestjs/common';
import {
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { AdminOnly } from '../auth/decorators/admin-only.decorator';
import { AdminDashboardService } from './admin-dashboard.service';
import { AdminUserDetailDto } from './dto/user-detail.dto';
import { AdminTripDetailDto } from './dto/trip-detail.dto';
import {
  AdminAnalyticsEventListQueryDto,
  AdminAnalyticsEventListResponseDto,
} from './dto/analytics-event-list.dto';
import {
  AdminAnalyticsSummaryDto,
  AdminAnalyticsSummaryQueryDto,
} from './dto/analytics-summary.dto';
import {
  AdminUserListQueryDto,
  AdminUserListResponseDto,
} from './dto/user-list.dto';
import {
  AdminUsersAggregatesDto,
  AdminUsersAggregatesQueryDto,
} from './dto/users-aggregates.dto';
import {
  AdminTripsAggregatesDto,
  AdminTripsAggregatesQueryDto,
} from './dto/trips-aggregates.dto';
import {
  AdminTripListQueryDto,
  AdminTripListResponseDto,
} from './dto/trip-list.dto';

@ApiTags('Admin Dashboard')
@Controller('admin/dashboard')
// Admin-only (see @AdminOnly on each route) read endpoints; CSV export
// paginates many sequential requests, which the global 10/min throttler
// would otherwise block.
@SkipThrottle()
export class AdminDashboardController {
  constructor(private readonly service: AdminDashboardService) {}

  @Get('users')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminListDashboardUsers',
    summary:
      'Paginated user list with subscription, scan credit, and trip count summaries.',
  })
  @ApiOkResponse({ type: AdminUserListResponseDto })
  listUsers(
    @Query() query: AdminUserListQueryDto,
  ): Promise<AdminUserListResponseDto> {
    return this.service.listUsers(query);
  }

  @Get('users/aggregates')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGetDashboardUsersAggregates',
    summary:
      'Aggregate user and subscription metrics: signups by day, auth-provider mix, subscription mix, new/churn, top active users.',
  })
  @ApiOkResponse({ type: AdminUsersAggregatesDto })
  getUsersAggregates(
    @Query() query: AdminUsersAggregatesQueryDto,
  ): Promise<AdminUsersAggregatesDto> {
    return this.service.getUsersAggregates(query);
  }

  @Get('trips')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminListDashboardTrips',
    summary:
      'Paginated trip list with creator, member count, expense count, status, currency, and dates.',
  })
  @ApiOkResponse({ type: AdminTripListResponseDto })
  listTrips(
    @Query() query: AdminTripListQueryDto,
  ): Promise<AdminTripListResponseDto> {
    return this.service.listTrips(query);
  }

  @Get('trips/aggregates')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGetDashboardTripsAggregates',
    summary:
      'Aggregate trip metrics: totals, trips-by-day, status mix, member engagement, expense totals by currency, and top destinations.',
  })
  @ApiOkResponse({ type: AdminTripsAggregatesDto })
  getTripsAggregates(
    @Query() query: AdminTripsAggregatesQueryDto,
  ): Promise<AdminTripsAggregatesDto> {
    return this.service.getTripsAggregates(query);
  }

  @Get('trips/:id')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGetDashboardTripDetail',
    summary:
      'Full detail for one trip: members, expenses, budgets, plan items, photos, notes, and activity (lists capped at 50 most recent).',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: AdminTripDetailDto })
  @ApiNotFoundResponse({ description: 'Trip not found' })
  getTripDetail(
    @Param('id', ParseIntPipe) id: number,
  ): Promise<AdminTripDetailDto> {
    return this.service.getTripDetail(id);
  }

  @Get('users/:id')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGetDashboardUserDetail',
    summary:
      'Full detail for one user: trips, subscription history, scan-credit ledger, and recent events (each capped at 50 most recent).',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: AdminUserDetailDto })
  @ApiNotFoundResponse({ description: 'User not found' })
  getUserDetail(
    @Param('id', ParseIntPipe) id: number,
  ): Promise<AdminUserDetailDto> {
    return this.service.getUserDetail(id);
  }

  @Get('analytics/events')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminListDashboardAnalyticsEvents',
    summary:
      'Paginated raw analytics event log with optional event-name / user / date filters.',
  })
  @ApiOkResponse({ type: AdminAnalyticsEventListResponseDto })
  listAnalyticsEvents(
    @Query() query: AdminAnalyticsEventListQueryDto,
  ): Promise<AdminAnalyticsEventListResponseDto> {
    return this.service.listAnalyticsEvents(query);
  }

  @Get('analytics/summary')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGetDashboardAnalyticsSummary',
    summary:
      'Aggregate analytics summary (totals, per-event-name counts, per-day time series) for a date window.',
  })
  @ApiOkResponse({ type: AdminAnalyticsSummaryDto })
  getAnalyticsSummary(
    @Query() query: AdminAnalyticsSummaryQueryDto,
  ): Promise<AdminAnalyticsSummaryDto> {
    return this.service.getAnalyticsSummary(query);
  }
}
