import { Module } from '@nestjs/common';
import { GeminiService } from './gemini.service';

// Shared Vertex AI (Gemini) access. ConfigModule is global, so no imports
// are needed. Consumed by BoardModule (video pin extraction) and
// ReceiptScanModule (receipt OCR); board.service also uses it for AI copy.
@Module({
  providers: [GeminiService],
  exports: [GeminiService],
})
export class GeminiModule {}
