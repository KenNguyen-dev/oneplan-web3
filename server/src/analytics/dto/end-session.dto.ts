import { ApiProperty } from '@nestjs/swagger';
import { IsDateString } from 'class-validator';

export class EndSessionDto {
  @ApiProperty({ description: 'ISO8601 client timestamp' })
  @IsDateString()
  endedAt: string;
}
