import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  ArrayNotEmpty,
  IsArray,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class UploadTelegramCodesDto {
  @ApiProperty({
    type: [String],
    description:
      'Apple one-time-use offer codes to add to the pool. Duplicates (already in the pool) are skipped.',
    maxItems: 25000,
  })
  @IsArray()
  @ArrayNotEmpty()
  @ArrayMaxSize(25000)
  @IsString({ each: true })
  @MaxLength(255, { each: true })
  codes: string[];

  @ApiPropertyOptional({
    description:
      'Optional label to group this batch of codes (e.g. campaign name).',
    maxLength: 100,
  })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  batchLabel?: string;
}

export class UploadTelegramCodesResultDto {
  @ApiProperty({ type: 'integer', description: 'Codes actually inserted.' })
  inserted: number;

  @ApiProperty({
    type: 'integer',
    description: 'Codes skipped because they were already in the pool.',
  })
  skipped: number;
}
