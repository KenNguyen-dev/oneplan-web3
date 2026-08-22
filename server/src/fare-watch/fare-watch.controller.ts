import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Public } from '../auth/decorators/public.decorator';
import { FareWatchService } from './fare-watch.service';
import {
  CreateFareWatchOrderDto,
  VerifyFareWatchOrderDto,
} from './dto/create-fare-watch-order.dto';

// Public endpoints on purpose: the /radar web page serves guests that have no
// OnePlan account. Guests prove ownership of the order via ZNS OTP; afterwards
// the unguessable publicId (cuid) is the capability to view/cancel it.
@ApiTags('fare-watch')
@Controller('fare-watch')
export class FareWatchController {
  constructor(private readonly fareWatch: FareWatchService) {}

  @Public()
  @Get('fares')
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @ApiOperation({
    summary: 'Public fares board: cached real prices for one route',
  })
  fares(
    @Query('origin') origin: string,
    @Query('destination') destination: string,
  ) {
    return this.fareWatch.fares(origin ?? '', destination ?? '');
  }

  @Public()
  @Post('orders')
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @ApiOperation({ summary: 'Create a fare watch (guest: sends ZNS OTP)' })
  @ApiOkResponse({ description: '{ publicId, status, needsOtp }' })
  create(@Body() dto: CreateFareWatchOrderDto) {
    return this.fareWatch.create(dto);
  }

  @Public()
  @Post('orders/verify')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({ summary: 'Verify guest OTP, activate the watch' })
  verify(@Body() dto: VerifyFareWatchOrderDto) {
    return this.fareWatch.verify(dto);
  }

  @Public()
  @Get('orders/:publicId')
  @ApiOperation({ summary: 'Watch status by its public id' })
  get(@Param('publicId') publicId: string) {
    return this.fareWatch.get(publicId);
  }

  @Public()
  @Delete('orders/:publicId')
  @ApiOperation({ summary: 'Cancel a watch' })
  cancel(@Param('publicId') publicId: string) {
    return this.fareWatch.cancel(publicId);
  }
}
