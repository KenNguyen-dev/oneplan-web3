import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEnum, IsInt, IsNumber, IsOptional, Min } from 'class-validator';
import { Currency, ListingTag } from '@prisma/client';

export class CreateTripRequestDto {
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

  @ApiProperty({ enum: ListingTag, enumName: 'ListingTag' })
  @IsEnum(ListingTag)
  tag: ListingTag;

  @ApiPropertyOptional({
    type: 'number',
    description: 'Requested budget in the given currency',
  })
  @IsOptional()
  @IsNumber()
  @Min(0)
  budget?: number;

  @ApiProperty({ enum: Currency, enumName: 'Currency' })
  @IsEnum(Currency)
  currency: Currency;
}
