import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class PlanRoutePinDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({
    type: 'integer',
    description: '1-based position in the route',
  })
  index: number;

  @ApiProperty()
  title: string;

  @ApiProperty({ type: 'number' })
  latitude: number;

  @ApiProperty({ type: 'number' })
  longitude: number;

  @ApiPropertyOptional()
  subtitle: string | null;

  @ApiPropertyOptional({ description: 'HH:MM format' })
  timeLabel: string | null;
}
