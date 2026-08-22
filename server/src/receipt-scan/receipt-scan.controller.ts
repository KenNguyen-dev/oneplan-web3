import {
  BadRequestException,
  Controller,
  Param,
  ParseIntPipe,
  Post,
  Req,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiBody,
  ApiConsumes,
  ApiForbiddenResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
  ApiUnprocessableEntityResponse,
} from '@nestjs/swagger';
import type { FastifyRequest } from 'fastify';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { ReceiptScanService } from './receipt-scan.service';
import { ScanReceiptDto } from './dto/scan-receipt.dto';
import { ReceiptScanResultDto } from './dto/receipt-scan-result.dto';

const ALLOWED_MIME_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/octet-stream',
];

const EXTENSION_MIME_MAP: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
};

@ApiBearerAuth()
@ApiTags('Receipt Scan')
@Controller('trips/:tripId/receipts')
export class ReceiptScanController {
  constructor(private readonly receiptScanService: ReceiptScanService) {}

  @Post('scan')
  @ApiConsumes('multipart/form-data')
  @ApiOperation({
    operationId: 'scanReceipt',
    summary: 'Scan a receipt image and extract line items using AI',
  })
  @ApiParam({ name: 'tripId', type: 'integer' })
  @ApiBody({ type: ScanReceiptDto })
  @ApiOkResponse({ type: ReceiptScanResultDto })
  @ApiForbiddenResponse({ description: 'Not a member of this trip' })
  @ApiUnprocessableEntityResponse({
    description: 'Could not extract items from receipt',
  })
  async scanReceipt(
    @CurrentUser('sub') userId: number,
    @Param('tripId', ParseIntPipe) tripId: number,
    @Req() req: FastifyRequest,
  ): Promise<ReceiptScanResultDto> {
    const file = await req.file();
    if (!file) {
      throw new BadRequestException('No image file provided');
    }
    let mimeType = file.mimetype;
    if (!ALLOWED_MIME_TYPES.includes(mimeType)) {
      throw new BadRequestException(
        'Invalid file type. Only JPEG, PNG, and WebP images are accepted.',
      );
    }
    if (mimeType === 'application/octet-stream' && file.filename) {
      const ext = '.' + file.filename.split('.').pop()?.toLowerCase();
      mimeType = EXTENSION_MIME_MAP[ext] ?? 'image/jpeg';
    }
    const buffer = await file.toBuffer();
    return this.receiptScanService.scanReceipt(
      tripId,
      userId,
      buffer,
      mimeType,
    );
  }
}
