import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Put,
  Query,
} from '@nestjs/common';
import {
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { AdminOnly } from '../auth/decorators/admin-only.decorator';
import {
  DeleteTelegramCodeResultDto,
  TelegramCodeListQueryDto,
  TelegramCodeListResponseDto,
} from './dto/telegram-code-list.dto';
import {
  TelegramSettingsDto,
  UpdateTelegramSettingsDto,
} from './dto/telegram-settings.dto';
import { TelegramStatsDto } from './dto/telegram-stats.dto';
import {
  UploadTelegramCodesDto,
  UploadTelegramCodesResultDto,
} from './dto/upload-codes.dto';
import { TelegramBotService } from './telegram-bot.service';
import { TelegramCodeService } from './telegram-code.service';
import { TelegramSettingsService } from './telegram-settings.service';

@ApiTags('Telegram')
@Controller('admin/telegram')
// Admin-only (see @AdminOnly on each route). The bulk upload + paginated list
// can issue several sequential requests, which the global 10/min throttler
// would otherwise block.
@SkipThrottle()
export class TelegramController {
  constructor(
    private readonly codes: TelegramCodeService,
    private readonly bot: TelegramBotService,
    private readonly settings: TelegramSettingsService,
  ) {}

  @Post('codes')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminUploadTelegramCodes',
    summary: 'Upload Apple offer codes into the bot pool (duplicates skipped).',
  })
  @ApiOkResponse({ type: UploadTelegramCodesResultDto })
  uploadCodes(
    @Body() body: UploadTelegramCodesDto,
  ): Promise<UploadTelegramCodesResultDto> {
    return this.codes.uploadCodes(body.codes, body.batchLabel);
  }

  @Get('codes')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminListTelegramCodes',
    summary: 'Paginated list of offer codes with assignment status.',
  })
  @ApiOkResponse({ type: TelegramCodeListResponseDto })
  listCodes(
    @Query() query: TelegramCodeListQueryDto,
  ): Promise<TelegramCodeListResponseDto> {
    return this.codes.listCodes(query);
  }

  @Delete('codes/:id')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminDeleteTelegramCode',
    summary: 'Remove a single offer code from the pool (assigned or not).',
  })
  @ApiParam({ name: 'id', type: Number, description: 'Offer code id.' })
  @ApiOkResponse({ type: DeleteTelegramCodeResultDto })
  deleteCode(
    @Param('id', ParseIntPipe) id: number,
  ): Promise<DeleteTelegramCodeResultDto> {
    return this.codes.deleteCode(id);
  }

  @Get('stats')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGetTelegramStats',
    summary:
      'Campaign stats: total/available/issued codes, per-batch breakdown, issued-by-day series.',
  })
  @ApiOkResponse({ type: TelegramStatsDto })
  async getStats(): Promise<TelegramStatsDto> {
    const { campaignEnabled } = await this.settings.resolve();
    return this.codes.stats({
      campaignEnabled,
      botEnabled: this.bot.isBotEnabled,
    });
  }

  @Get('settings')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGetTelegramSettings',
    summary: 'Get the editable campaign settings (toggle, greeting, CTA).',
  })
  @ApiOkResponse({ type: TelegramSettingsDto })
  async getSettings(): Promise<TelegramSettingsDto> {
    const s = await this.settings.resolve();
    return {
      campaignEnabled: s.campaignEnabled,
      welcomeText: s.welcomeText,
      cta: s.cta,
    };
  }

  @Put('settings')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminUpdateTelegramSettings',
    summary: 'Update the campaign settings (applies live, no redeploy).',
  })
  @ApiOkResponse({ type: TelegramSettingsDto })
  async updateSettings(
    @Body() body: UpdateTelegramSettingsDto,
  ): Promise<TelegramSettingsDto> {
    const s = await this.settings.update(body);
    return {
      campaignEnabled: s.campaignEnabled,
      welcomeText: s.welcomeText,
      cta: s.cta,
    };
  }
}
