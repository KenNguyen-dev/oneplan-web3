import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { JournalLabel, JournalStatus } from '@prisma/client';

export class JournalDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  slug: string;

  @ApiProperty()
  title: string;

  @ApiProperty({ enum: JournalLabel, enumName: 'JournalLabel' })
  label: JournalLabel;

  @ApiPropertyOptional({ nullable: true })
  excerpt: string | null;

  @ApiProperty({ description: 'Body of the post (HTML or Markdown).' })
  content: string;

  @ApiPropertyOptional({
    nullable: true,
    description: 'Signed download URL for the cover image; null when none.',
  })
  coverImageUrl: string | null;

  @ApiProperty({ enum: JournalStatus, enumName: 'JournalStatus' })
  status: JournalStatus;

  @ApiPropertyOptional({ nullable: true, description: 'ISO 8601 timestamp.' })
  publishedAt: string | null;

  @ApiProperty({ description: 'ISO 8601 timestamp.' })
  createdAt: string;

  @ApiProperty({ description: 'ISO 8601 timestamp.' })
  updatedAt: string;
}
