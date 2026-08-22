import { ApiProperty } from '@nestjs/swagger';
import { ArrayMinSize, IsArray, IsInt, Min } from 'class-validator';

export class InviteMembersDto {
  @ApiProperty({ type: [Number], description: 'Array of user IDs to invite' })
  @IsArray()
  @ArrayMinSize(1)
  @IsInt({ each: true })
  @Min(1, { each: true })
  userIds: number[];
}
