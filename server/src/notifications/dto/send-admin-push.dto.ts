import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  ArrayNotEmpty,
  IsArray,
  IsEnum,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';
import { NoProfanity } from '../../common/validators/no-profanity.decorator';

export enum AdminPushAudience {
  ALL = 'ALL',
  TARGETED = 'TARGETED',
}

export enum AdminPushDestination {
  BOARD = 'BOARD',
  MARKET = 'MARKET',
}

export class SendAdminPushDto {
  @ApiProperty({
    enum: AdminPushAudience,
    description: 'ALL broadcasts to every device; TARGETED uses `recipients`.',
  })
  @IsEnum(AdminPushAudience)
  audience: AdminPushAudience;

  @ApiProperty({ maxLength: 120 })
  @IsString()
  @IsNotEmpty()
  @MaxLength(120)
  @NoProfanity()
  title: string;

  @ApiProperty({ maxLength: 500 })
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  @NoProfanity()
  body: string;

  @ApiPropertyOptional({
    enum: AdminPushDestination,
    description: 'Screen the push opens on tap. Omit to just open the app.',
  })
  @IsOptional()
  @IsEnum(AdminPushDestination)
  destination?: AdminPushDestination;

  @ApiPropertyOptional({
    description:
      'Marketplace listing the push opens on tap. Only used when destination=MARKET; older app builds without listing routing fall back to the Market tab.',
  })
  @IsOptional()
  @IsInt()
  @Min(1)
  listingId?: number;

  @ApiPropertyOptional({
    enum: ['ios', 'android'],
    description:
      'Restrict broadcast to a single platform. Omit to send to all platforms.',
  })
  @IsOptional()
  @IsIn(['ios', 'android'])
  platform?: 'ios' | 'android';

  @ApiPropertyOptional({
    type: [String],
    description:
      'Required when audience=TARGETED. Each entry is an email or numeric user ID.',
  })
  @ValidateIf(
    (o: SendAdminPushDto) => o.audience === AdminPushAudience.TARGETED,
  )
  @IsArray()
  @ArrayNotEmpty()
  @IsString({ each: true })
  recipients?: string[];
}
