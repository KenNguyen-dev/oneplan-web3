import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiNoContentResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { ClsService } from 'nestjs-cls';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AnalyticsService } from './analytics.service';
import { EndSessionDto } from './dto/end-session.dto';
import { StartSessionDto } from './dto/start-session.dto';
import { TrackEventsDto } from './dto/track-events.dto';

@ApiTags('Analytics')
@ApiBearerAuth()
@Controller('analytics')
export class AnalyticsController {
  constructor(
    private readonly analytics: AnalyticsService,
    private readonly cls: ClsService,
  ) {}

  @Post('sessions')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'startAnalyticsSession',
    summary: 'Register a new analytics session (idempotent on id)',
  })
  @ApiNoContentResponse()
  async startSession(
    @CurrentUser('sub') userId: number,
    @Body() dto: StartSessionDto,
  ): Promise<void> {
    await this.analytics.startSession(dto, userId);
  }

  @Patch('sessions/:id/end')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'endAnalyticsSession',
    summary: 'Mark an analytics session as ended',
  })
  @ApiNoContentResponse()
  async endSession(
    @Param('id') sessionId: string,
    @Body() dto: EndSessionDto,
  ): Promise<void> {
    await this.analytics.endSession(sessionId, new Date(dto.endedAt));
  }

  @Post('events')
  @HttpCode(HttpStatus.NO_CONTENT)
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @ApiOperation({
    operationId: 'trackAnalyticsEvents',
    summary: 'Submit a batch of client-emitted analytics events (max 50)',
  })
  @ApiNoContentResponse()
  @ApiOkResponse({ description: 'Events recorded' })
  async trackEvents(
    @CurrentUser('sub') userId: number,
    @Body() dto: TrackEventsDto,
  ): Promise<void> {
    const sessionId = this.cls.get<string>('sessionId') ?? null;
    await this.analytics.recordClientEvents(dto.events, { userId, sessionId });
  }
}
