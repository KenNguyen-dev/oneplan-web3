import { Body, Controller, Get, Post } from '@nestjs/common';
import {
  ApiCreatedResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AdminOnly } from '../auth/decorators/admin-only.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { GiftDto, GiftLogDto, GiftResultDto } from './dto/gift.dto';
import { GiftService } from './gift.service';

@ApiTags('Gift Admin')
@Controller('gift/admin')
export class GiftController {
  constructor(private readonly giftService: GiftService) {}

  @Post()
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGiftUser',
    summary:
      'Gift a user free scan credits and/or a Pro package by email (loyalty reward).',
  })
  @ApiCreatedResponse({ type: GiftResultDto })
  @ApiNotFoundResponse({ description: 'No user with that email' })
  gift(
    @Body() dto: GiftDto,
    @CurrentUser('email') adminEmail: string,
  ): Promise<GiftResultDto> {
    return this.giftService.gift(dto, adminEmail);
  }

  @Get()
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminListGifts',
    summary: 'Recent gift history, newest first.',
  })
  @ApiOkResponse({ type: [GiftLogDto] })
  list(): Promise<GiftLogDto[]> {
    return this.giftService.listGifts();
  }
}
