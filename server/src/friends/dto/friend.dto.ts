import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class FriendUserDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional()
  avatarUrl: string | null;

  @ApiProperty({ description: 'Whether user has active Pro subscription' })
  isPro: boolean;
}

export class FriendDto {
  @ApiProperty({ type: 'integer' })
  friendshipId: number;

  @ApiProperty({ type: FriendUserDto })
  user: FriendUserDto;

  @ApiProperty({ type: 'integer' })
  mutualFriendCount: number;

  @ApiProperty()
  createdAt: string;
}
