import { ApiProperty } from '@nestjs/swagger';

export class PublicFriendPreviewDto {
  @ApiProperty()
  displayName: string;

  @ApiProperty({ type: 'integer' })
  tripCount: number;
}
