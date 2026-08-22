import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';
import { NoProfanity } from '../../common/validators/no-profanity.decorator';

export class UpdateTripNoteDto {
  @ApiPropertyOptional({ maxLength: 255 })
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(255)
  @NoProfanity()
  title?: string;

  @ApiPropertyOptional({ maxLength: 2000 })
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  @NoProfanity()
  body?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isDone?: boolean;
}
