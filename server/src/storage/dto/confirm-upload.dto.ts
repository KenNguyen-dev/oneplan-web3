import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, IsString, Min } from 'class-validator';
import { UploadTarget } from '../constants/upload-targets';

export class ConfirmUploadDto {
  /** The upload target type */
  @ApiProperty({ enum: UploadTarget, enumName: 'UploadTarget' })
  @IsEnum(UploadTarget)
  target: UploadTarget;

  /** Entity ID */
  @ApiProperty({ type: 'integer' })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  entityId: number;

  /** The S3 object key returned from presign */
  @ApiProperty()
  @IsString()
  objectKey: string;

  /** Optional caption (for trip photos) */
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  caption?: string;
}
