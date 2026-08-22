import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class ExpenseShareDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional()
  avatarUrl: string | null;

  @ApiProperty({ type: 'number' })
  shareAmount: number;

  @ApiProperty()
  isSettled: boolean;

  @ApiPropertyOptional()
  settledAt: string | null;
}
