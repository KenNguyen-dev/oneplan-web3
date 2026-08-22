import { ApiProperty } from '@nestjs/swagger';
import { IsBoolean } from 'class-validator';

export class RespondFriendRequestDto {
  @ApiProperty({ description: 'True to accept, false to decline' })
  @IsBoolean()
  accept: boolean;
}
