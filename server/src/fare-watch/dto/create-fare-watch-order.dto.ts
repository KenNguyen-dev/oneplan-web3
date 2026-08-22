import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  Length,
  Matches,
  Max,
  Min,
} from 'class-validator';

export class CreateFareWatchOrderDto {
  @ApiProperty({ example: 'SGN', description: 'IATA code of origin airport' })
  @IsString()
  @Length(3, 3)
  @Matches(/^[A-Za-z]{3}$/)
  origin!: string;

  @ApiProperty({ example: 'HAN' })
  @IsString()
  @Length(3, 3)
  @Matches(/^[A-Za-z]{3}$/)
  destination!: string;

  @ApiProperty({ example: '2026-08-08', description: 'Earliest travel date' })
  @IsISO8601()
  dateFrom!: string;

  @ApiProperty({ example: '2026-08-13', description: 'Latest travel date' })
  @IsISO8601()
  dateTo!: string;

  @ApiProperty({
    example: 899000,
    description: 'Target price in VND per passenger, one-way',
  })
  @IsInt()
  @Min(200_000)
  @Max(50_000_000)
  targetPrice!: number;

  @ApiPropertyOptional({
    example: 'Nam',
    description:
      'Display name used to personalize Zalo alerts (ZNS templates require a customer-name param).',
  })
  @IsOptional()
  @IsString()
  @Length(1, 60)
  name?: string;

  @ApiPropertyOptional({
    example: '0912345678',
    description:
      'Vietnamese phone for Zalo alerts. Required for guests; optional for logged-in app users (push is used instead).',
  })
  @IsOptional()
  @Matches(/^(0|84)\d{8,10}$/)
  phone?: string;

  @ApiPropertyOptional({ description: 'OnePlan trip id (app flow only)' })
  @IsOptional()
  @IsInt()
  tripId?: number;
}

export class VerifyFareWatchOrderDto {
  @ApiProperty()
  @IsString()
  @Length(8, 64)
  publicId!: string;

  @ApiProperty({ example: '2468' })
  @IsString()
  @Matches(/^\d{4}$/)
  otp!: string;
}
