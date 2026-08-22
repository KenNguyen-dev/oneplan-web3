import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  Delete,
  Get,
  HttpCode,
  MessageEvent,
  Param,
  Post,
  Sse,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiBody,
  ApiCreatedResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Observable, map } from 'rxjs';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import {
  ActivePinExtractionResponseDto,
  PinExtractionSessionDto,
} from './dto/extracted-pin.dto';
import {
  ExtractPinsRequestDto,
  StartPinExtractionResponseDto,
} from './dto/extract-pins-request.dto';
import {
  InsufficientScanCreditsErrorDto,
  ScanCreditBalanceDto,
} from '../scan-credit/dto/scan-credit-balance.dto';
import { ScanCreditService } from '../scan-credit/scan-credit.service';
import { PinExtractionService } from './pin-extraction.service';
import { VideoResolverError } from './video-resolver.service';

// Rate-limit cap of 20 extractions per user per 24h. Gemini video analysis is
// paid per input token — this prevents a runaway client from racking real
// cost. Tune in app.module global throttler limits if needed.
const RATE_LIMIT_TTL_MS = 24 * 60 * 60 * 1000;
const RATE_LIMIT_COUNT = 20;

@ApiBearerAuth()
@ApiTags('Board / Pin Extraction')
@Controller('board/pins/extract')
export class PinExtractionController {
  constructor(
    private readonly extractionService: PinExtractionService,
    private readonly scanCredit: ScanCreditService,
  ) {}

  @Post()
  @Throttle({
    default: { limit: RATE_LIMIT_COUNT, ttl: RATE_LIMIT_TTL_MS },
  })
  @ApiOperation({
    operationId: 'startPinExtraction',
    summary:
      'Validate a pasted Instagram/TikTok URL and create an extraction session. Open the GET /:sessionId/stream endpoint to receive pins. Returns the existing sessionId if the user already has one for the same URL.',
  })
  @ApiBody({ type: ExtractPinsRequestDto })
  @ApiCreatedResponse({ type: StartPinExtractionResponseDto })
  @ApiResponse({
    status: 402,
    description: 'The user has no scan credits available.',
    type: InsufficientScanCreditsErrorDto,
  })
  async start(
    @CurrentUser('sub') userId: number,
    @Body() body: ExtractPinsRequestDto,
  ): Promise<StartPinExtractionResponseDto> {
    try {
      return await this.extractionService.startSession(body.sourceUrl, userId);
    } catch (err) {
      if (err instanceof ConflictException) {
        // Re-throw with the sessionId in the body so the iOS client can
        // navigate the user back to the in-flight extraction.
        throw err;
      }
      if (err instanceof VideoResolverError) {
        throw new BadRequestException({
          code: err.code,
          message: err.message,
        });
      }
      throw err;
    }
  }

  @Get('active')
  @ApiOperation({
    operationId: 'getActivePinExtraction',
    summary:
      "Returns the caller's most recent non-dismissed extraction session under `session`, or an empty envelope when there isn't one.",
  })
  @ApiOkResponse({ type: ActivePinExtractionResponseDto })
  async active(
    @CurrentUser('sub') userId: number,
  ): Promise<ActivePinExtractionResponseDto> {
    const session = await this.extractionService.getActiveSession(userId);
    return { session: session ?? undefined };
  }

  @Get('quota')
  @ApiOperation({
    operationId: 'getPinExtractionQuota',
    summary:
      "Returns the caller's available scan-credit balance and, while a Pro subscription is active, the next weekly grant timestamp.",
  })
  @ApiOkResponse({ type: ScanCreditBalanceDto })
  async getQuota(
    @CurrentUser('sub') userId: number,
  ): Promise<ScanCreditBalanceDto> {
    const balance = await this.scanCredit.getBalance(userId);
    return {
      available: balance.available,
      nextProGrantAt: balance.nextProGrantAt
        ? balance.nextProGrantAt.toISOString()
        : null,
    };
  }

  @Get(':sessionId')
  @ApiOperation({
    operationId: 'getPinExtraction',
    summary:
      'Returns the full state of an extraction session (phase, pins, status). Used by iOS to render a session that may already be terminal.',
  })
  @ApiParam({ name: 'sessionId', type: 'string' })
  @ApiOkResponse({ type: PinExtractionSessionDto })
  async get(
    @CurrentUser('sub') userId: number,
    @Param('sessionId') sessionId: string,
  ): Promise<PinExtractionSessionDto> {
    return this.extractionService.getSession(sessionId, userId);
  }

  @Delete(':sessionId')
  @HttpCode(204)
  @ApiOperation({
    operationId: 'cancelPinExtraction',
    summary:
      'Cancel a running session OR dismiss a terminal one. Idempotent — both states converge on "card disappears from BoardView".',
  })
  @ApiParam({ name: 'sessionId', type: 'string' })
  async cancel(
    @CurrentUser('sub') userId: number,
    @Param('sessionId') sessionId: string,
  ): Promise<void> {
    await this.extractionService.cancelOrDismissSession(sessionId, userId);
  }

  @Sse(':sessionId/stream')
  @ApiOperation({
    operationId: 'streamPinExtraction',
    summary:
      'Server-Sent Events stream of extraction status and pins for a previously-started session.',
  })
  @ApiParam({ name: 'sessionId', type: 'string' })
  stream(
    @CurrentUser('sub') userId: number,
    @Param('sessionId') sessionId: string,
  ): Observable<MessageEvent> {
    return this.extractionService.stream(sessionId, userId).pipe(
      map((event) => ({
        type: event.type,
        data: event.data as MessageEvent['data'],
      })),
    );
  }
}
