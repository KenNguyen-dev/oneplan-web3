import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class TripNoteDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  tripId: number;

  @ApiProperty({ type: 'integer' })
  createdById: number;

  @ApiProperty()
  title: string;

  @ApiPropertyOptional()
  body: string | null;

  @ApiProperty()
  isDone: boolean;

  @ApiProperty()
  createdAt: string;

  @ApiProperty()
  updatedAt: string;
}
