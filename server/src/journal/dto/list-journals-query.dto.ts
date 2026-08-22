import { ApiPropertyOptional } from '@nestjs/swagger';
import { JournalLabel, JournalStatus } from '@prisma/client';
import { IsEnum, IsOptional } from 'class-validator';

export class ListJournalsQueryDto {
  @ApiPropertyOptional({ enum: JournalStatus, enumName: 'JournalStatus' })
  @IsOptional()
  @IsEnum(JournalStatus)
  status?: JournalStatus;

  @ApiPropertyOptional({ enum: JournalLabel, enumName: 'JournalLabel' })
  @IsOptional()
  @IsEnum(JournalLabel)
  label?: JournalLabel;
}
