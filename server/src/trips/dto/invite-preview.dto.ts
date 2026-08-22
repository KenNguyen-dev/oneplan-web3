import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { TripStatus } from '@prisma/client';

export class InvitePreviewDto {
  @ApiProperty()
  name: string;

  @ApiPropertyOptional()
  coverImageUrl: string | null;

  @ApiProperty({ type: 'integer' })
  memberCount: number;

  @ApiProperty({ enum: TripStatus, enumName: 'TripStatus' })
  status: TripStatus;
}
