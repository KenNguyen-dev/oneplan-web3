import { ApiProperty } from '@nestjs/swagger';

export class UploadResultDto {
  /** The presigned download URL */
  @ApiProperty()
  url: string;

  /** The S3 object key */
  @ApiProperty()
  objectKey: string;
}
