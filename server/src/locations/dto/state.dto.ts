import { ApiProperty } from '@nestjs/swagger';

export class StateDto {
  @ApiProperty({ type: 'integer' })
  id: number;

  name: string;
  iso2: string | null;
  type: string | null;

  @ApiProperty({ type: 'string', nullable: true })
  latitude: string | null;

  @ApiProperty({ type: 'string', nullable: true })
  longitude: string | null;
}
