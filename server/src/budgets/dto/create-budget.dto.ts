import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Currency, PlanScope } from '@prisma/client';
import {
  IsDefined,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';

export class CreateBudgetDto {
  @ApiProperty({ maxLength: 255 })
  @IsString()
  @MaxLength(255)
  name: string;

  @ApiProperty({
    type: 'number',
    description: 'Positive amount with up to 2 decimal places',
  })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  amount: number;

  @ApiPropertyOptional({
    enum: PlanScope,
    enumName: 'PlanScope',
    default: PlanScope.GROUP,
  })
  @IsOptional()
  @IsEnum(PlanScope)
  scope?: PlanScope;

  @ApiPropertyOptional({
    type: 'number',
    description:
      'Amount the user typed in their original currency. Must be provided together with originalCurrency.',
  })
  @ValidateIf((o) => o.originalCurrency !== undefined)
  @IsDefined({
    message: 'originalAmount is required when originalCurrency is provided',
  })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  originalAmount?: number;

  @ApiPropertyOptional({
    enum: Currency,
    enumName: 'Currency',
    description:
      'Currency of the original amount. Must be provided together with originalAmount.',
  })
  @ValidateIf((o) => o.originalAmount !== undefined)
  @IsDefined({
    message: 'originalCurrency is required when originalAmount is provided',
  })
  @IsEnum(Currency)
  originalCurrency?: Currency;
}
