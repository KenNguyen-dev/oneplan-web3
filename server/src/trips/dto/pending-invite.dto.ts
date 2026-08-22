import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class PendingTripInviteDto {
  @ApiProperty()
  inviteCode: string;

  @ApiProperty()
  tripName: string;

  @ApiPropertyOptional()
  coverImageUrl: string | null;

  @ApiProperty()
  invitedByDisplayName: string;
}
