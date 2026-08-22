import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ChatMessageDto } from './chat-message.dto';

export class ChatMessageListDto {
  @ApiProperty({ type: [ChatMessageDto] })
  data: ChatMessageDto[];

  @ApiPropertyOptional({ type: 'integer', nullable: true })
  nextCursor: number | null;
}
