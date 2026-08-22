import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class TelegramBatchStatDto {
  @ApiPropertyOptional({
    nullable: true,
    type: String,
    description: 'Batch label (null for codes uploaded without one).',
  })
  batchLabel: string | null;

  @ApiProperty({ type: 'integer' })
  total: number;

  @ApiProperty({ type: 'integer' })
  issued: number;

  @ApiProperty({ type: 'integer' })
  available: number;
}

export class TelegramIssuedByDayDto {
  @ApiProperty({ description: 'YYYY-MM-DD in UTC' })
  day: string;

  @ApiProperty({ type: 'integer' })
  count: number;
}

export class TelegramStatsDto {
  @ApiProperty({
    description:
      'Whether the campaign (button + code handout) is currently enabled.',
  })
  campaignEnabled: boolean;

  @ApiProperty({
    description: 'Whether the bot poller is enabled in this environment.',
  })
  botEnabled: boolean;

  @ApiProperty({ type: 'integer', description: 'Total codes in the pool.' })
  totalCodes: number;

  @ApiProperty({ type: 'integer', description: 'Codes not yet assigned.' })
  available: number;

  @ApiProperty({
    type: 'integer',
    description: 'Codes assigned to a Telegram user.',
  })
  issued: number;

  @ApiProperty({ type: [TelegramBatchStatDto] })
  byBatch: TelegramBatchStatDto[];

  @ApiProperty({ type: [TelegramIssuedByDayDto] })
  issuedByDay: TelegramIssuedByDayDto[];
}
