import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ChatMessageType } from '@prisma/client';

export class ChatMessageDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  tripId: number;

  @ApiPropertyOptional({ type: 'integer', nullable: true })
  senderId: number | null;

  @ApiProperty()
  senderDisplayName: string;

  @ApiPropertyOptional()
  senderAvatarUrl: string | null;

  @ApiProperty({ maxLength: 2000 })
  content: string;

  @ApiProperty({ enum: ChatMessageType, enumName: 'ChatMessageType' })
  type: ChatMessageType;

  @ApiPropertyOptional()
  imageUrl: string | null;

  @ApiProperty()
  createdAt: string;
}
