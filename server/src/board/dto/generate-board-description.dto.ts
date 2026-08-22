import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MaxLength } from 'class-validator';

export class GenerateBoardDescriptionDto {
  @ApiProperty({ maxLength: 255 })
  @IsString()
  @MaxLength(255)
  title: string;

  @ApiProperty({ maxLength: 255 })
  @IsString()
  @MaxLength(255)
  countryName: string;

  @ApiPropertyOptional({ maxLength: 255 })
  @IsOptional()
  @IsString()
  @MaxLength(255)
  stateName?: string;

  @ApiPropertyOptional({ maxLength: 255 })
  @IsOptional()
  @IsString()
  @MaxLength(255)
  cityName?: string;
}

export class BoardDescriptionDto {
  @ApiProperty({ maxLength: 500 })
  description: string;
}
