import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ExpenseCategory } from '@prisma/client';
import { ExpensePaidByDto } from './expense.dto';

export class SharedMemberPreviewDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiPropertyOptional()
  avatarUrl: string | null;
}

export class ExpenseSummaryDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty()
  name: string;

  @ApiProperty({ type: 'number' })
  amount: number;

  @ApiProperty({ enum: ExpenseCategory, enumName: 'ExpenseCategory' })
  category: ExpenseCategory;

  @ApiProperty()
  expenseDate: string;

  @ApiProperty()
  createdAt: string;

  @ApiPropertyOptional({ type: ExpensePaidByDto, nullable: true })
  paidBy: ExpensePaidByDto | null;

  @ApiProperty({ type: [SharedMemberPreviewDto] })
  sharedMembers: SharedMemberPreviewDto[];
}
