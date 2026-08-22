import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { TripPhotoDto } from './trip-photo.dto';

export class TripPhotoListDto {
  @ApiProperty({ type: [TripPhotoDto] })
  data: TripPhotoDto[];

  @ApiPropertyOptional({ type: 'integer', nullable: true })
  nextCursor: number | null;
}
