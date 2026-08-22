import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { InviteStatus, TripMemberRole } from '@prisma/client';

export class TripMemberDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional()
  avatarUrl: string | null;

  @ApiPropertyOptional()
  friendCode: string | null;

  @ApiProperty({ enum: InviteStatus, enumName: 'InviteStatus' })
  inviteStatus: InviteStatus;

  @ApiProperty({ enum: TripMemberRole, enumName: 'TripMemberRole' })
  role: TripMemberRole;

  @ApiPropertyOptional()
  joinedAt: string | null;

  @ApiProperty({ description: 'Whether user has active Pro subscription' })
  isPro: boolean;
}
