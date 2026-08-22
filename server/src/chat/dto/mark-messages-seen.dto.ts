import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, Min } from 'class-validator';

export class MarkMessagesSeenDto {
  @ApiProperty({
    description:
      'Highest chat message ID the current user has seen for this trip',
    type: 'integer',
  })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  messageId: number;
}
