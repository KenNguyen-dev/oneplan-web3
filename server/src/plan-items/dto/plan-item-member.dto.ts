import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class PlanItemMemberDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  @ApiProperty({ type: 'integer' })
  userId: number;

  @ApiProperty()
  displayName: string;

  @ApiPropertyOptional()
  avatarUrl: string | null;
}
