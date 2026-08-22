import { Module } from '@nestjs/common';
import { GeminiModule } from '../common/gemini/gemini.module';
import { ReceiptScanController } from './receipt-scan.controller';
import { ReceiptScanService } from './receipt-scan.service';

@Module({
  imports: [GeminiModule],
  controllers: [ReceiptScanController],
  providers: [ReceiptScanService],
})
export class ReceiptScanModule {}
