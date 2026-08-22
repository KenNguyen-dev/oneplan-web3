import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Query,
} from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { AdminOnly } from '../auth/decorators/admin-only.decorator';
import { FulfillTripRequestDto } from './dto/fulfill-trip-request.dto';
import { ListTripRequestsQueryDto } from './dto/list-trip-requests-query.dto';
import { TripRequestDto, TripRequestListDto } from './dto/trip-request.dto';
import { TripRequestsService } from './trip-requests.service';

@ApiTags('Trip Requests Admin')
@Controller('trip-requests/admin')
export class TripRequestsAdminController {
  constructor(private readonly tripRequestsService: TripRequestsService) {}

  @Get()
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminListTripRequests',
    summary: 'List trip requests, optionally filtered by status.',
  })
  @ApiOkResponse({ type: TripRequestListDto })
  adminListTripRequests(
    @Query() query: ListTripRequestsQueryDto,
  ): Promise<TripRequestListDto> {
    return this.tripRequestsService.adminList(
      query.status,
      query.page ?? 1,
      query.pageSize ?? 50,
    );
  }

  @Post(':id/fulfill')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminFulfillTripRequest',
    summary:
      'Mark a trip request as fulfilled with an APPROVED marketplace listing and notify the requester via push (deep-links to the listing).',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: TripRequestDto })
  @ApiNotFoundResponse({ description: 'Trip request or listing not found' })
  @ApiBadRequestResponse({ description: 'Listing is not APPROVED' })
  adminFulfillTripRequest(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: FulfillTripRequestDto,
  ): Promise<TripRequestDto> {
    return this.tripRequestsService.adminFulfill(id, dto.listingId);
  }

  @Post(':id/reject')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminRejectTripRequest',
    summary: 'Mark a trip request as rejected.',
  })
  @ApiParam({ name: 'id', type: 'integer' })
  @ApiOkResponse({ type: TripRequestDto })
  @ApiNotFoundResponse({ description: 'Trip request not found' })
  adminRejectTripRequest(
    @Param('id', ParseIntPipe) id: number,
  ): Promise<TripRequestDto> {
    return this.tripRequestsService.adminReject(id);
  }
}
