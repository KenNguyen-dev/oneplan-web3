import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { JournalLabel } from '@prisma/client';
import {
  IsEnum,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

export class CreateJournalDto {
  @ApiProperty({ maxLength: 255 })
  @IsString()
  @MinLength(1)
  @MaxLength(255)
  title: string;

  @ApiProperty({ enum: JournalLabel, enumName: 'JournalLabel' })
  @IsEnum(JournalLabel)
  label: JournalLabel;

  @ApiPropertyOptional({ maxLength: 500 })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  excerpt?: string;

  @ApiProperty({ description: 'Body of the post (HTML or Markdown).' })
  @IsString()
  @MinLength(1)
  content: string;

  @ApiPropertyOptional({
    description: 'URL slug. Auto-generated from the title when omitted.',
    maxLength: 255,
  })
  @IsOptional()
  @IsString()
  @MaxLength(255)
  slug?: string;
}
