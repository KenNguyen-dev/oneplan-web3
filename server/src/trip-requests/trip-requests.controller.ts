import { Body, Controller, Post } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { CreateTripRequestDto } from './dto/create-trip-request.dto';
import { TripRequestDto } from './dto/trip-request.dto';
import { TripRequestsService } from './trip-requests.service';

@ApiTags('Trip Requests')
@ApiBearerAuth()
@Controller('trip-requests')
export class TripRequestsController {
  constructor(private readonly tripRequestsService: TripRequestsService) {}

  @Post()
  @ApiOperation({
    operationId: 'createTripRequest',
    summary: 'Submit a trip plan request for a destination.',
  })
  @ApiCreatedResponse({ type: TripRequestDto })
  @ApiBadRequestResponse({
    description: 'No destination (cityId/stateId/countryId) provided',
  })
  @ApiConflictResponse({
    description: 'User already has an OPEN request for the same destination',
  })
  createTripRequest(
    @CurrentUser('sub') userId: number,
    @Body() dto: CreateTripRequestDto,
  ): Promise<TripRequestDto> {
    return this.tripRequestsService.create(userId, dto);
  }
}
