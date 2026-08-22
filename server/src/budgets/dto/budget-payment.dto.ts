import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class BudgetPaymentDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional()
  avatarUrl: string | null;

  @ApiProperty({ type: 'number' })
  amount: number;

  @ApiProperty()
  isPaid: boolean;

  @ApiPropertyOptional()
  paidAt: string | null;
}
