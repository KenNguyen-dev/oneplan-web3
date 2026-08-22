import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AdminOnly } from '../auth/decorators/admin-only.decorator';
import { AdminDeviceTokenCountsDto } from './dto/admin-device-token-counts.dto';
import { AdminPushResultDto } from './dto/admin-push-result.dto';
import { SendAdminPushDto } from './dto/send-admin-push.dto';
import { NotificationsService } from './notifications.service';

@ApiTags('Notifications Admin')
@Controller('notifications/admin')
export class NotificationsAdminController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Get('token-counts')
  @AdminOnly()
  @ApiOperation({
    operationId: 'adminGetTokenCounts',
    summary: 'Device token counts by platform (ios / android / total).',
  })
  @ApiOkResponse({ type: AdminDeviceTokenCountsDto })
  getTokenCounts(): Promise<AdminDeviceTokenCountsDto> {
    return this.notificationsService.getDeviceTokenCounts();
  }

  @Post('push')
  @AdminOnly()
  @HttpCode(HttpStatus.OK)
  // Global ThrottlerGuard is on; cap to avoid accidental double-broadcasts.
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @ApiOperation({
    operationId: 'adminSendPush',
    summary:
      'Send an admin push notification (broadcast to all or targeted recipients).',
  })
  @ApiOkResponse({ type: AdminPushResultDto })
  send(@Body() dto: SendAdminPushDto): Promise<AdminPushResultDto> {
    return this.notificationsService.sendAdminPush(dto);
  }
}
