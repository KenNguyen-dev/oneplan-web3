import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class TripPhotoDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  tripId: number;

  @ApiProperty({ description: 'Presigned download URL' })
  url: string;

  @ApiPropertyOptional()
  caption: string | null;

  @ApiProperty({ type: 'integer' })
  uploadedById: number;

  @ApiProperty()
  uploaderDisplayName: string;

  @ApiPropertyOptional()
  uploaderAvatarUrl: string | null;

  @ApiProperty()
  createdAt: string;
}
