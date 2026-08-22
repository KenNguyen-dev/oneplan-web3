import { ApiPropertyOptional } from '@nestjs/swagger';

export class PlanRouteLegDto {
  @ApiPropertyOptional({ description: "Google's encoded polyline string" })
  polyline: string | null;

  @ApiPropertyOptional({ type: 'integer' })
  durationSec: number | null;

  @ApiPropertyOptional({ type: 'number' })
  distanceM: number | null;
}
