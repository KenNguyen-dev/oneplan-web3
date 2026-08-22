import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class BreakdownExpenseItemDto {
  @ApiProperty({ type: 'integer' })
  expenseId: number;

  @ApiProperty()
  expenseName: string;

  @ApiProperty({ type: 'number' })
  shareAmount: number;

  @ApiProperty()
  isSettled: boolean;

  @ApiProperty({ type: 'integer' })
  shareId: number;
}

export class MemberBreakdownDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional()
  avatarUrl: string | null;

  @ApiProperty({ type: 'number' })
  totalDeposit: number;

  @ApiProperty({ type: 'number' })
  totalPaid: number;

  @ApiProperty({ type: 'number' })
  totalShare: number;

  @ApiProperty({ type: 'number' })
  netBalance: number;

  @ApiProperty()
  isAllSettled: boolean;

  @ApiProperty({ type: [BreakdownExpenseItemDto] })
  expenses: BreakdownExpenseItemDto[];
}

export class TripBreakdownDto {
  @ApiProperty({ type: 'number' })
  totalSpent: number;

  @ApiProperty({ type: 'integer' })
  unsettledCount: number;

  @ApiProperty({ type: [MemberBreakdownDto] })
  members: MemberBreakdownDto[];
}
