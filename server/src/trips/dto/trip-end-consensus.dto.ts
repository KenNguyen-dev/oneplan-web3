import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { TripEndRequestStatus, TripEndVoteDecision } from '@prisma/client';
import { IsEnum } from 'class-validator';

import { CashDebtDto } from '../../trip-vault/dto/settlement.dto';
import { VaultHistoryEntryDto } from '../../trip-vault/dto/vault-history.dto';

export class CastTripEndVoteDto {
  @ApiProperty({
    enum: TripEndVoteDecision,
    enumName: 'TripEndVoteDecision',
  })
  @IsEnum(TripEndVoteDecision)
  decision: TripEndVoteDecision;
}

export class TripEndVoteMemberDto {
  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional({ nullable: true })
  avatarUrl: string | null;

  @ApiPropertyOptional({
    enum: TripEndVoteDecision,
    enumName: 'TripEndVoteDecision',
    nullable: true,
    description: 'Null while this member has not voted yet',
  })
  decision: TripEndVoteDecision | null;
}

export class TripEndRequestDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  tripId: number;

  @ApiProperty({ type: 'integer' })
  requestedBy: number;

  @ApiProperty({
    enum: TripEndRequestStatus,
    enumName: 'TripEndRequestStatus',
  })
  status: TripEndRequestStatus;

  @ApiProperty()
  createdAt: string;

  @ApiPropertyOptional({ nullable: true })
  resolvedAt: string | null;

  @ApiPropertyOptional({
    enum: TripEndVoteDecision,
    enumName: 'TripEndVoteDecision',
    nullable: true,
  })
  myDecision: TripEndVoteDecision | null;

  @ApiProperty({ type: 'integer' })
  approvedCount: number;

  @ApiProperty({ type: 'integer' })
  memberCount: number;

  @ApiProperty({ type: TripEndVoteMemberDto, isArray: true })
  members: TripEndVoteMemberDto[];
}

export class TripEndReviewDto {
  @ApiProperty({ type: TripEndRequestDto })
  request: TripEndRequestDto;

  @ApiProperty({ type: VaultHistoryEntryDto, isArray: true })
  history: VaultHistoryEntryDto[];

  @ApiProperty({
    type: CashDebtDto,
    isArray: true,
    description:
      'Off-chain pay/receive rows relevant to the caller after vault settlement',
  })
  mySettlement: CashDebtDto[];

  @ApiProperty({ description: 'Vault balance in micro-USDC' })
  balanceMicro: string;
}
