import { ApiProperty } from '@nestjs/swagger';
import { TripNoteDto } from './trip-note.dto';

export class TripNoteListDto {
  @ApiProperty({ type: [TripNoteDto] })
  data: TripNoteDto[];
}
