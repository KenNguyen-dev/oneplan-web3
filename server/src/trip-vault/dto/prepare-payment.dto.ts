import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ExpenseCategory } from '@prisma/client';
import {
  IsArray,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';

export class PreparePaymentDto {
  @ApiProperty({
    description: 'Raw EMVCo payload scanned from the VietQR code',
  })
  @IsString()
  qrPayload: string;

  @ApiPropertyOptional({ description: 'Amount in VND as a decimal string' })
  @IsOptional()
  @Matches(/^\d+$/)
  amountVnd?: string;

  @ApiProperty({ description: 'Expense name shown in the trip ledger' })
  @IsString()
  @MaxLength(255)
  name: string;

  @ApiProperty({ enum: ExpenseCategory, enumName: 'ExpenseCategory' })
  @IsEnum(ExpenseCategory)
  category: ExpenseCategory;

  // `type: 'integer', isArray: true` rather than `type: [Number]`: the latter
  // emits `number`, which swift-openapi-generator maps to Double, and user ids
  // are integers.
  // Empty means shared by everyone — same convention as settlement math,
  // vault history, and UpdateVaultSpendDto. The iOS "All" chip sends [].
  @ApiProperty({
    type: 'integer',
    isArray: true,
    description:
      'User ids the expense is split across. Empty array means shared by everyone.',
  })
  @IsArray()
  @IsInt({ each: true })
  shareWithUserIds: number[];
}

export class PreparePaymentResponseDto {
  @ApiProperty({
    description: 'Base64 legacy transaction for the client to sign',
  })
  base64Tx: string;

  @ApiProperty()
  vaultTransactionId: number;

  @ApiProperty({ description: 'True when a second member must approve' })
  needsApproval: boolean;
}

export class SubmitSignedDto {
  @ApiProperty({
    description: 'Base64 transaction with the client signature added',
  })
  @IsString()
  signedTx: string;
}

export class DepositRequestDto {
  @ApiProperty({ description: 'Amount in micro-USDC as a decimal string' })
  @Matches(/^\d+$/)
  amountMicro: string;
}

export class UnsignedTxDto {
  @ApiProperty({
    description: 'Base64 legacy transaction for the client to sign',
  })
  base64Tx: string;
}

export class SubmitResultDto {
  @ApiProperty({ description: 'PENDING, CONFIRMED or FAILED' })
  status: string;
}

export class SubmitDepositDto {
  @ApiProperty({
    description: 'Base64 transaction with the client signature added',
  })
  @IsString()
  signedTx: string;

  // Recorded for display only. The program enforces the real amount on chain,
  // and the reconcile job's drift check catches a row that disagrees with the
  // vault balance, so a client that lies here corrects itself rather than
  // moving money.
  @ApiProperty({ description: 'Amount in micro-USDC as a decimal string' })
  @Matches(/^\d+$/)
  amountMicro: string;
}

export class DepositResultDto {
  @ApiProperty({ description: 'On-chain signature of the confirmed deposit' })
  signature: string;
}

export class SyncMembersResultDto {
  @ApiProperty({ description: 'How many members were added on chain' })
  added: number;
}
