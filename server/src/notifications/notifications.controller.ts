import {
  Body,
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  Post,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiCreatedResponse,
  ApiNoContentResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { NotificationsService } from './notifications.service';
import { RegisterTokenDto } from './dto/register-token.dto';

@ApiBearerAuth()
@ApiTags('Devices')
@Controller('devices')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Post('token')
  @ApiOperation({
    operationId: 'registerDeviceToken',
    summary: 'Register a device push token',
  })
  @ApiCreatedResponse()
  async registerToken(
    @CurrentUser('sub') userId: number,
    @Body() dto: RegisterTokenDto,
  ): Promise<void> {
    await this.notificationsService.registerToken(
      userId,
      dto.token,
      dto.platform ?? 'ios',
      dto.locale,
    );
  }

  @Delete('token')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'unregisterDeviceToken',
    summary: 'Unregister a device push token',
  })
  @ApiNoContentResponse()
  async unregisterToken(
    @CurrentUser('sub') userId: number,
    @Body() dto: RegisterTokenDto,
  ): Promise<void> {
    await this.notificationsService.unregisterToken(userId, dto.token);
  }
}
