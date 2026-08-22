import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsInt } from 'class-validator';

export class SettlementPayoutDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional({ nullable: true })
  avatarUrl: string | null;

  @ApiPropertyOptional({
    nullable: true,
    description: 'Solana address the payout goes to; null when unlinked',
  })
  walletAddress: string | null;

  @ApiProperty({
    description:
      'What this member is owed overall, in micro-USDC as a decimal string. ' +
      'Negative means they owe the group.',
  })
  netMicro: string;

  @ApiProperty({
    description: 'Paid on chain from the vault, in micro-USDC',
  })
  onChainMicro: string;

  @ApiProperty({
    description:
      'Still owed after the vault is emptied, in micro-USDC. Settled off ' +
      'chain, because the vault can pay out but cannot collect.',
  })
  offChainMicro: string;
}

export class CashDebtLineDto {
  @ApiProperty({ description: 'Expense / payment title' })
  title: string;

  @ApiProperty({
    description:
      'Portion of the cash debt attributed to this line, micro-USDC string. ' +
      'All lines on a debt sum to amountMicro.',
  })
  amountMicro: string;
}

export class CashDebtDto {
  @ApiProperty({ type: 'integer', description: 'Who owes the money' })
  fromUserId: number;

  @ApiProperty()
  fromDisplayName: string;

  @ApiProperty({ type: 'integer', description: 'Who is owed it' })
  toUserId: number;

  @ApiProperty()
  toDisplayName: string;

  @ApiProperty({ description: 'Amount in micro-USDC as a decimal string' })
  amountMicro: string;

  @ApiProperty({ description: 'The creditor has confirmed receiving this' })
  isConfirmed: boolean;

  @ApiProperty({
    description:
      'True only for the creditor. Nobody else may confirm a debt was paid.',
  })
  canConfirm: boolean;

  @ApiProperty({
    type: CashDebtLineDto,
    isArray: true,
    description:
      'Per-expense breakdown that sums to amountMicro (debtor share weights)',
  })
  lines: CashDebtLineDto[];

  @ApiPropertyOptional({
    nullable: true,
    description:
      'Creditor OnePlan Wallet address when linked — enables Send for the debtor',
  })
  toWalletAddress: string | null;
}

export class ConfirmCashDebtDto {
  @ApiProperty({ type: 'integer', description: 'Who paid the caller' })
  @IsInt()
  fromUserId: number;
}

export class SettlementPreviewDto {
  @ApiProperty({ description: 'Vault balance in micro-USDC' })
  balanceMicro: string;

  @ApiProperty({
    description: 'Sum of the on-chain payouts, in micro-USDC',
  })
  totalOnChainMicro: string;

  @ApiProperty({
    description:
      'Total the group still owes each other after settlement, in micro-USDC',
  })
  totalOffChainMicro: string;

  @ApiProperty({ type: SettlementPayoutDto, isArray: true })
  payouts: SettlementPayoutDto[];

  @ApiProperty({
    description:
      'False when something would block server settlement (empty vault ' +
      'without wallets, too many recipients, etc.)',
  })
  canSettle: boolean;

  @ApiPropertyOptional({
    nullable: true,
    description: 'Why settlement is blocked, when it is',
  })
  blockedReason: string | null;

  @ApiProperty({
    description:
      'Whether the vault has distributed and closed. Until it has, every net ' +
      'position still moves with the next payment, so the cash debts below are ' +
      'a forecast rather than a bill.',
  })
  isSettled: boolean;

  @ApiProperty({
    type: CashDebtDto,
    isArray: true,
    description:
      'What the vault cannot cover, as concrete debts between two people',
  })
  cashDebts: CashDebtDto[];
}
