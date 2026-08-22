import { ApiProperty } from '@nestjs/swagger';

export class StartTripConflictErrorDto {
  @ApiProperty({ example: 400 })
  statusCode: number;

  @ApiProperty({ example: 'MEMBER_CONFLICT' })
  error: string;

  @ApiProperty({ type: [String], example: ['Ken', 'Mai'] })
  memberNames: string[];
}
