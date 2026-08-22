import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Post,
  Query,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiForbiddenResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { ChatService } from './chat.service';
import { ListMessagesQueryDto } from './dto/list-messages-query.dto';
import { ChatMessageListDto } from './dto/chat-message-list.dto';
import { MarkMessagesSeenDto } from './dto/mark-messages-seen.dto';

@ApiBearerAuth()
@ApiTags('Chat')
@Controller('trips/:tripId/messages')
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  @Get()
  @ApiOperation({
    operationId: 'listMessages',
    summary: 'List chat messages for a trip',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiOkResponse({ type: ChatMessageListDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  listMessages(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Query() query: ListMessagesQueryDto,
  ): Promise<ChatMessageListDto> {
    return this.chatService.listMessages(
      tripId,
      userId,
      query.cursor,
      query.take,
    );
  }

  @Post('seen')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    operationId: 'markMessagesSeen',
    summary: 'Mark chat messages as seen for a trip',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiNoContentResponse()
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiNotFoundResponse({ description: 'Message not found in this trip' })
  async markMessagesSeen(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Body() dto: MarkMessagesSeenDto,
  ): Promise<void> {
    await this.chatService.markMessagesSeen(tripId, userId, dto.messageId);
  }
}
