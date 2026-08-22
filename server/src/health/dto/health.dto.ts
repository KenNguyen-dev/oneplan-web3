import { ApiPropertyOptional } from '@nestjs/swagger';

export class LiveResponseDto {
  /** Service liveness status */
  status: string;

  /** Server commit hash for the running deployment */
  @ApiPropertyOptional({
    nullable: true,
    example: 'abc1234def5678',
  })
  commitHash: string | null;
}

export class ReadyResponseDto {
  /** Service readiness status */
  status: string;

  /** Database connection status */
  database: string;
}
