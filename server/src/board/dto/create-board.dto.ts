import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsInt, IsOptional, IsString, IsUrl, MaxLength } from 'class-validator';

export class CreateBoardDto {
  @ApiProperty({ maxLength: 255 })
  @IsString()
  @MaxLength(255)
  title: string;

  @ApiPropertyOptional({ maxLength: 500 })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @ApiPropertyOptional({ maxLength: 500 })
  @IsOptional()
  @IsUrl()
  @MaxLength(500)
  coverImageUrl?: string;

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
