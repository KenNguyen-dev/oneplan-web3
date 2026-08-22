import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Currency, ExpenseCategory } from '@prisma/client';
import { ExpenseShareDto } from './expense-share.dto';

export class ExpensePaidByDto {
  @ApiPropertyOptional({ type: 'integer', nullable: true })
  userId: number | null;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional({ nullable: true })
  avatarUrl: string | null;
}

export class ExpenseDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  tripId: number;

  @ApiProperty()
  name: string;

  @ApiProperty({ type: 'number' })
  amount: number;

  @ApiProperty({ enum: ExpenseCategory, enumName: 'ExpenseCategory' })
  category: ExpenseCategory;

  @ApiPropertyOptional()
  note: string | null;

  @ApiPropertyOptional()
  receiptUrl: string | null;

  @ApiProperty()
  expenseDate: string;

  @ApiProperty()
  createdAt: string;

  @ApiPropertyOptional({ type: ExpensePaidByDto, nullable: true })
  paidBy: ExpensePaidByDto | null;

  @ApiProperty({ type: [ExpenseShareDto] })
  shares: ExpenseShareDto[];

  @ApiPropertyOptional({
    type: 'number',
    description: 'Amount in the original currency the user typed.',
  })
  originalAmount?: number;

  @ApiPropertyOptional({ enum: Currency, enumName: 'Currency' })
  originalCurrency?: Currency;

  @ApiPropertyOptional({
    type: 'number',
    description:
      'Exchange rate used to convert originalAmount → amount (in trip currency).',
  })
  exchangeRate?: number;

  @ApiPropertyOptional({
    type: 'boolean',
    description:
      'Present (and true) only on the immediate response of a create/update that used a stale/fallback exchange rate. Never present on reads.',
  })
  rateStale?: boolean;
}
