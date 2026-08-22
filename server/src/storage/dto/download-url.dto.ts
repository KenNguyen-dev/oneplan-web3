import { ApiProperty } from '@nestjs/swagger';

export class DownloadUrlDto {
  /** Presigned download URL */
  @ApiProperty()
  url: string;

  /** Seconds until URL expires */
  @ApiProperty({ type: 'integer' })
  expiresIn: number;
}
