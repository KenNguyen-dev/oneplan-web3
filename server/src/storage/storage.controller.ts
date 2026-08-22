import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { StorageService } from './storage.service';
import { PresignUploadDto } from './dto/presign-upload.dto';
import { PresignedUrlDto } from './dto/presigned-url.dto';
import { ConfirmUploadDto } from './dto/confirm-upload.dto';
import { UploadResultDto } from './dto/upload-result.dto';
import { GetDownloadUrlDto } from './dto/get-download-url.dto';
import { DownloadUrlDto } from './dto/download-url.dto';

@ApiBearerAuth()
@ApiTags('Uploads')
@Controller('uploads')
export class StorageController {
  constructor(private readonly storageService: StorageService) {}

  @Post('presign')
  @HttpCode(200)
  @ApiOperation({
    operationId: 'createPresignedUpload',
    summary: 'Generate a presigned URL for direct upload to storage',
  })
  @ApiOkResponse({ type: PresignedUrlDto })
  @ApiBadRequestResponse({
    description: 'Invalid target, content type, or entity',
  })
  presign(
    @Body() dto: PresignUploadDto,
    @CurrentUser('email') userEmail: string,
  ): Promise<PresignedUrlDto> {
    return this.storageService.createPresignedUpload(dto, userEmail);
  }

  @Post('confirm')
  @HttpCode(200)
  @ApiOperation({
    operationId: 'confirmUpload',
    summary: 'Confirm a completed upload and persist the URL to the database',
  })
  @ApiOkResponse({ type: UploadResultDto })
  @ApiNotFoundResponse({
    description: 'Object not found in storage',
  })
  confirm(
    @Body() dto: ConfirmUploadDto,
    @CurrentUser('sub') userId: number,
    @CurrentUser('email') userEmail: string,
  ): Promise<UploadResultDto> {
    return this.storageService.confirmUpload(dto, userId, userEmail);
  }

  @Get('url')
  @ApiOperation({
    operationId: 'getDownloadUrl',
    summary: 'Generate a presigned download URL for a stored object',
  })
  @ApiOkResponse({ type: DownloadUrlDto })
  getDownloadUrl(@Query() query: GetDownloadUrlDto): Promise<DownloadUrlDto> {
    return this.storageService.getSignedDownloadUrl(query.objectKey);
  }
}
