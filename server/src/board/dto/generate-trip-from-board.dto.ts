import { ApiProperty } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class GenerateTripFromBoardDto {
  @ApiProperty({
    type: 'array',
    items: { type: 'integer' },
    description: 'IDs of the board pins to arrange into the trip',
    minItems: 1,
    maxItems: 40,
  })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(40)
  @IsInt({ each: true })
  pinIds: number[];

  @ApiProperty({
    type: 'integer',
    minimum: 1,
    maximum: 14,
    description: 'How many days to spread the pins across',
  })
  @IsInt()
  @Min(1)
  @Max(14)
  dayCount: number;

  @ApiProperty({ maxLength: 255, description: 'Name for the new trip' })
  @IsString()
  @MaxLength(255)
  tripName: string;

  @ApiProperty({
    type: 'boolean',
    required: false,
    default: false,
    description:
      'When true, the AI may add clearly-marked suggested venues to fill ' +
      'empty meal/sightseeing slots. Defaults to false (pins only).',
  })
  @IsOptional()
  @IsBoolean()
  fillGaps?: boolean;
}
