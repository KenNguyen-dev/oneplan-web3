import { ApiProperty } from '@nestjs/swagger';

export class PresignedUrlDto {
  /** The presigned URL to PUT the file to */
  @ApiProperty()
  uploadUrl: string;

  /** The S3 object key (needed for confirm step) */
  @ApiProperty()
  objectKey: string;

  /** URL expiry in seconds */
  @ApiProperty({ type: 'integer' })
  expiresIn: number;
}
