import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, ValidateNested } from 'class-validator';
import { TrackEventDto } from './track-event.dto';

export class TrackEventsDto {
  @ApiProperty({ type: [TrackEventDto], maxItems: 50 })
  @ValidateNested({ each: true })
  @Type(() => TrackEventDto)
  @ArrayMinSize(1)
  @ArrayMaxSize(50)
  events: TrackEventDto[];
}
