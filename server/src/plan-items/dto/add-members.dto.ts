import { ApiProperty } from '@nestjs/swagger';
import { ArrayMinSize, IsArray, IsInt, Min } from 'class-validator';

export class AddMembersDto {
  @ApiProperty({ type: [Number], description: 'User IDs to add as members' })
  @IsArray()
  @ArrayMinSize(1)
  @IsInt({ each: true })
  @Min(1, { each: true })
  userIds: number[];
}
