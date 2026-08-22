import { ApiProperty } from '@nestjs/swagger';
import { IsString } from 'class-validator';

export class GetDownloadUrlDto {
  /** S3 object key */
  @ApiProperty()
  @IsString()
  objectKey: string;
}
