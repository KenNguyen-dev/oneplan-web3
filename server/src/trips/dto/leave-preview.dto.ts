import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class LeavePreviewBudgetDto {
  @ApiProperty()
  budgetName: string;

  @ApiProperty({ type: 'number' })
  amount: number;

  @ApiProperty()
  isPaid: boolean;

  @ApiProperty({ type: 'number' })
  refundAmount: number;
}

/** One vault ledger row shown on the leave breakdown sheet. */
export class LeaveLedgerLineDto {
  @ApiProperty()
  title: string;

  @ApiProperty({ description: 'Signed micro-USDC (deposit +, spend share −)' })
  amountMicro: string;

  @ApiPropertyOptional({
    description:
      'Signed VND display amount for spends (member share of amountVnd). Null for deposits/settlements.',
  })
  amountVnd?: string | null;

  @ApiProperty({ description: 'DEPOSIT | SPEND | SETTLEMENT' })
  kind: string;

  @ApiProperty({ description: 'HH:mm local display time' })
  time: string;

  @ApiPropertyOptional({
    description: 'Share chip ("All") or wallet address for deposits',
  })
  subtitle?: string | null;

  @ApiPropertyOptional({ description: 'Expense category for spend icons' })
  category?: string | null;
}

export class LeavePreviewDto {
  @ApiProperty()
  displayName: string;

  @ApiProperty({ type: [LeavePreviewBudgetDto] })
  budgets: LeavePreviewBudgetDto[];

  @ApiProperty({
    type: 'number',
    description: 'Total budget amount you paid (refundable)',
  })
  totalBudgetRefund: number;

  @ApiProperty({
    type: 'number',
    description: 'Total budget amount not yet paid (cancelled)',
  })
  totalBudgetCancelled: number;

  @ApiProperty({
    type: 'number',
    description: 'Your total expense share (what you consumed)',
  })
  totalExpenseShare: number;

  @ApiProperty({
    type: 'number',
    description: 'Net settlement: Budget refund minus expense share',
  })
  netSettlement: number;

  @ApiProperty({
    description: 'True when this trip has a group vault (web3 leave rules)',
  })
  hasVault: boolean;

  @ApiPropertyOptional({
    description: 'Signed vault position in micro-USDC (deposit − spend share)',
  })
  netMicro?: string;

  @ApiPropertyOptional({
    description:
      'micro-USDC the member must deposit before announce (max(0,-net))',
  })
  owedMicro?: string;

  @ApiProperty({
    type: [LeaveLedgerLineDto],
    description: 'Vault rows for the leave breakdown (empty for classic trips)',
  })
  lines: LeaveLedgerLineDto[];

  @ApiProperty({
    description:
      'Whether the member may call announce (vault: net>=0 and no pending request)',
  })
  canAnnounce: boolean;

  @ApiProperty({
    description: 'Member already announced; waiting on host confirm',
  })
  leaveRequestPending: boolean;

  @ApiProperty({
    description:
      'Whether DELETE member will succeed now (classic leave, or vault cleared legacy)',
  })
  canLeave: boolean;

  @ApiPropertyOptional({
    nullable: true,
    description:
      'owes_group | group_owes_you | leave_pending when vault leave is blocked',
  })
  blockReason?: string | null;

  @ApiProperty({
    description: 'Host has marked this member vault-cleared for leave',
  })
  vaultLeaveCleared: boolean;
}

export class LeaveSettlementExpenseDto {
  @ApiProperty()
  expenseName: string;

  @ApiProperty({ type: 'number' })
  shareAmount: number;

  @ApiProperty()
  isSettled: boolean;
}

export class LeaveSettlementDto {
  @ApiProperty()
  displayName: string;

  @ApiProperty({ type: 'number', description: 'Total budget amount refunded' })
  totalBudgetRefund: number;

  @ApiProperty({
    type: 'number',
    description: 'Your total expense share (what you consumed)',
  })
  totalExpenseShare: number;

  @ApiProperty({
    type: 'number',
    description: 'Net settlement: Budget refund minus expense share',
  })
  netSettlement: number;

  @ApiProperty({ type: [LeaveSettlementExpenseDto] })
  expenses: LeaveSettlementExpenseDto[];
}

export class VaultLeaveClearResultDto {
  @ApiProperty()
  cleared: boolean;
}

export class VaultLeaveRequestDto {
  @ApiProperty({ type: 'integer' })
  tripId: number;

  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional({ nullable: true })
  avatarUrl?: string | null;

  @ApiProperty({
    description: 'Live signed net micro-USDC (deposit − spend share)',
  })
  netMicro: string;

  @ApiProperty({
    description:
      'READY: latest vault DEPOSIT micro-USDC from history. PAYOUT: credit to send.',
  })
  announcedNetMicro: string;

  @ApiProperty({
    description: 'WAITING_DEPOSIT | READY | PAYOUT | DONE (template statuses)',
  })
  status: string;

  @ApiPropertyOptional({
    nullable: true,
    description: 'Member OnePlan wallet (for PAYOUT address check)',
  })
  walletAddress?: string | null;

  @ApiProperty()
  requestedAt: string;
}

export class VaultLeaveRequestListDto {
  @ApiProperty({ type: [VaultLeaveRequestDto] })
  items: VaultLeaveRequestDto[];
}

export class VaultLeaveAnnounceResultDto {
  @ApiProperty({ type: VaultLeaveRequestDto })
  request: VaultLeaveRequestDto;
}

export class VaultLeaveConfirmResultDto {
  @ApiProperty()
  completed: boolean;

  @ApiPropertyOptional({
    description: 'Set when a vault payout was required (net > 0)',
  })
  payoutPending?: boolean;
}
