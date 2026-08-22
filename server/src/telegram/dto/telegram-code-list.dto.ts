import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export enum TelegramCodeStatus {
  available = 'available',
  assigned = 'assigned',
}

export class TelegramCodeListQueryDto {
  @ApiPropertyOptional({ type: 'integer', minimum: 1, default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({
    type: 'integer',
    minimum: 1,
    maximum: 100,
    default: 25,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 25;

  @ApiPropertyOptional({
    enum: TelegramCodeStatus,
    enumName: 'TelegramCodeStatus',
    description: 'Filter by assignment status.',
  })
  @IsOptional()
  @IsEnum(TelegramCodeStatus)
  status?: TelegramCodeStatus;

  @ApiPropertyOptional({ description: 'Match against the batch label.' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  batchLabel?: string;

  @ApiPropertyOptional({
    description: 'Case-insensitive substring match against the code.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  search?: string;
}

export class TelegramOfferCodeItemDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  code: string;

  @ApiPropertyOptional({ nullable: true, type: String })
  batchLabel: string | null;

  @ApiProperty({ enum: TelegramCodeStatus, enumName: 'TelegramCodeStatus' })
  status: TelegramCodeStatus;

  @ApiPropertyOptional({
    nullable: true,
    type: String,
    description:
      'Telegram user id (serialized as a string — it can exceed 2^53).',
  })
  assignedTelegramUserId: string | null;

  @ApiPropertyOptional({ nullable: true, type: String })
  assignedTelegramUsername: string | null;

  @ApiPropertyOptional({ nullable: true, type: Date })
  assignedAt: Date | null;

  @ApiProperty()
  createdAt: Date;
}

export class DeleteTelegramCodeResultDto {
  @ApiProperty({
    description: 'True if a code was removed, false if not found.',
  })
  deleted: boolean;
}

export class TelegramCodeListResponseDto {
  @ApiProperty({ type: [TelegramOfferCodeItemDto] })
  items: TelegramOfferCodeItemDto[];

  @ApiProperty({ type: 'integer' })
  total: number;

  @ApiProperty({ type: 'integer' })
  page: number;

  @ApiProperty({ type: 'integer' })
  limit: number;
}
