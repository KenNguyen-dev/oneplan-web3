import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsInt, IsOptional, IsString, MaxLength } from 'class-validator';

export class UpdateBoardDto {
  @ApiPropertyOptional({ maxLength: 255 })
  @IsOptional()
  @IsString()
  @MaxLength(255)
  title?: string;

  @ApiPropertyOptional({ maxLength: 500 })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @ApiPropertyOptional({ type: 'integer' })
  @IsOptional()
  @IsInt()
  cityId?: number;

  @ApiPropertyOptional({ type: 'integer' })
  @IsOptional()
  @IsInt()
  stateId?: number;

  @ApiPropertyOptional({ type: 'integer' })
  @IsOptional()
  @IsInt()
  countryId?: number;
}
