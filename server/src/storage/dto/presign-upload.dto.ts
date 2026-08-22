import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, IsString, Min } from 'class-validator';
import { UploadTarget } from '../constants/upload-targets';

export class PresignUploadDto {
  /** The type of upload target */
  @ApiProperty({ enum: UploadTarget, enumName: 'UploadTarget' })
  @IsEnum(UploadTarget)
  target: UploadTarget;

  /** The entity ID (userId for avatar, tripId for cover/photo, expenseId for receipt) */
  @ApiProperty({ type: 'integer' })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  entityId: number;

  /** MIME type of the file to upload */
  @ApiProperty({ example: 'image/jpeg' })
  @IsString()
  contentType: string;

  /** Optional filename */
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  filename?: string;
}
