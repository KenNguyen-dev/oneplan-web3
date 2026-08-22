import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsDateString,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

export class StartSessionDto {
  @ApiProperty({ description: 'Client-generated UUIDv4 session id' })
  @IsUUID('4')
  id: string;

  @ApiProperty({ enum: ['ios', 'web', 'android'] })
  @IsIn(['ios', 'web', 'android'])
  platform: 'ios' | 'web' | 'android';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(32)
  appVersion?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(32)
  osVersion?: string;

  @ApiPropertyOptional({ description: 'Pre-auth device identifier (UUIDv4)' })
  @IsOptional()
  @IsUUID('4')
  anonymousId?: string;

  @ApiProperty({ description: 'ISO8601 client timestamp' })
  @IsDateString()
  startedAt: string;
}
