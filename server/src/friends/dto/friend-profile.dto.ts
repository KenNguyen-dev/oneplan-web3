import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class FriendProfileFriendEntryDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional()
  avatarUrl: string | null;

  @ApiProperty({ type: 'integer' })
  friendCount: number;

  @ApiProperty({ type: 'integer' })
  mutualFriendCount: number;

  @ApiProperty({ description: 'Whether user has active Pro subscription' })
  isPro: boolean;
}

export class FriendProfileDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional()
  avatarUrl: string | null;

  @ApiPropertyOptional()
  friendCode: string | null;

  @ApiProperty()
  memberSince: string;

  @ApiProperty({ type: 'integer' })
  tripCount: number;

  @ApiProperty({ type: 'integer' })
  cityCount: number;

  @ApiProperty({ type: 'integer' })
  friendCount: number;

  @ApiProperty({
    enum: ['none', 'pending_sent', 'pending_received', 'friends'],
  })
  requestStatus: 'none' | 'pending_sent' | 'pending_received' | 'friends';

  @ApiPropertyOptional({ type: 'integer', nullable: true })
  friendshipId: number | null;

  @ApiPropertyOptional({ type: 'integer', nullable: true })
  friendRequestId: number | null;

  @ApiProperty({ type: [FriendProfileFriendEntryDto] })
  friends: FriendProfileFriendEntryDto[];

  @ApiProperty({ description: 'Whether user has active Pro subscription' })
  isPro: boolean;
}
