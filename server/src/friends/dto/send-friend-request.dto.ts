import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString } from 'class-validator';

export class SendFriendRequestDto {
  @ApiProperty({ description: 'Friend code of the user to add' })
  @IsString()
  @IsNotEmpty()
  friendCode: string;
}
