import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class FriendPreviewDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional()
  avatarUrl: string | null;

  @ApiProperty()
  memberSince: string;

  @ApiProperty({ type: 'integer' })
  mutualFriendCount: number;

  @ApiProperty({ type: 'integer' })
  tripCount: number;

  @ApiProperty({ type: 'integer' })
  countryCount: number;

  @ApiProperty({ type: 'integer' })
  cityCount: number;

  @ApiProperty({
    enum: ['none', 'pending_sent', 'pending_received', 'friends'],
  })
  requestStatus: 'none' | 'pending_sent' | 'pending_received' | 'friends';
}
