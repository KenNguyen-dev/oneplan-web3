import {
  ForbiddenException,
  Injectable,
  UnprocessableEntityException,
  BadGatewayException,
  GatewayTimeoutException,
} from '@nestjs/common';
import { InviteStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AnalyticsService } from '../analytics/analytics.service';
import { ANALYTICS_EVENTS } from '../analytics/constants/events';
import { GeminiService } from '../common/gemini/gemini.service';
import { ReceiptScanResultDto } from './dto/receipt-scan-result.dto';

const SCAN_TIMEOUT_MS = 30_000;

// Gemini wants UPPERCASE string types in response schemas. Mirrors
// ReceiptScanResultDto so the model returns exactly the shape we parse.
const RECEIPT_RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    items: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        required: ['name', 'quantity', 'unitPrice', 'totalPrice'],
        properties: {
          name: { type: 'STRING' },
          quantity: { type: 'NUMBER' },
          unitPrice: { type: 'NUMBER' },
          totalPrice: { type: 'NUMBER' },
        },
      },
    },
    subtotal: { type: 'NUMBER' },
    tax: { type: 'NUMBER' },
    total: { type: 'NUMBER' },
    currency: { type: 'STRING' },
    restaurantName: { type: 'STRING' },
  },
};

const SYSTEM_PROMPT = `You are a receipt parser. Extract line items from the receipt image and return valid JSON.

Return this exact JSON structure:
{
  "items": [
    { "name": "Item Name", "quantity": 1, "unitPrice": 25000, "totalPrice": 25000 }
  ],
  "subtotal": 95000,
  "tax": 9500,
  "total": 104500,
  "currency": "VND",
  "restaurantName": "Store Name"
}

Rules:
- Read every price EXACTLY as printed on the receipt, as a decimal number. Do NOT convert to cents/satang or any subunit; do NOT multiply or divide. Strip thousands separators, keep the decimal point. Examples: a line printed "950.00" → 950, "1,234.50" → 1234.5, "25,000" → 25000.
- Keep "name" and "restaurantName" EXACTLY as printed on the receipt, in the original language and script (e.g. keep Thai as Thai). Do NOT translate, transliterate, anglicize, or paraphrase. Preserve diacritics and tone marks exactly.
- If quantity is not explicit, assume 1
- totalPrice = quantity × unitPrice
- The price printed next to an item is almost always the LINE TOTAL (already multiplied by quantity), not the unit price. Only treat it as a unit price if the receipt explicitly has separate "Unit Price" and "Total" columns.
- If subtotal, tax, or total are not visible, omit them (do not guess)
- If currency is not clear, omit it
- Return an empty items array if no items can be extracted`;

@Injectable()
export class ReceiptScanService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly analytics: AnalyticsService,
    private readonly gemini: GeminiService,
  ) {}

  async scanReceipt(
    tripId: number,
    userId: number,
    imageBuffer: Buffer,
    mimeType: string,
  ): Promise<ReceiptScanResultDto> {
    await this.assertMember(tripId, userId);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), SCAN_TIMEOUT_MS);

    try {
      const parsed = await this.gemini.generateJson<ReceiptScanResultDto>({
        imageBytes: imageBuffer,
        mimeType,
        prompt: SYSTEM_PROMPT,
        responseSchema: RECEIPT_RESPONSE_SCHEMA,
        signal: controller.signal,
      });

      if (!parsed.items || parsed.items.length === 0) {
        throw new UnprocessableEntityException(
          'No items detected in the receipt',
        );
      }

      const result = this.validateAndCorrectPrices(parsed);

      void this.analytics.track(ANALYTICS_EVENTS.BILL_SCANNED, {
        userId,
        properties: {
          tripId,
          itemCount: result.items.length,
          currency: result.currency ?? null,
        },
      });

      return result;
    } catch (error) {
      if (error.name === 'AbortError') {
        throw new GatewayTimeoutException(
          'Receipt scanning timed out. Please try again.',
        );
      }
      if (
        error instanceof UnprocessableEntityException ||
        error instanceof BadGatewayException ||
        error instanceof ForbiddenException
      ) {
        throw error;
      }
      throw new BadGatewayException(
        'Failed to process receipt. Please try again.',
      );
    } finally {
      clearTimeout(timeout);
    }
  }

  private validateAndCorrectPrices(
    parsed: ReceiptScanResultDto,
  ): ReceiptScanResultDto {
    // Prefer subtotal (excludes tax), fall back to total
    const reference = parsed.subtotal ?? parsed.total;
    if (!reference || reference <= 0) return parsed;

    const itemsSum = parsed.items.reduce(
      (sum, item) => sum + item.totalPrice,
      0,
    );
    const tolerance = reference * 0.02;

    // Already matches — no correction needed
    if (Math.abs(itemsSum - reference) <= tolerance) return parsed;

    // Only attempt correction if sum overshoots (the typical misinterpretation)
    if (itemsSum <= reference) return parsed;

    // Find indices of multi-quantity items (only these are ambiguous)
    const ambiguousIdx = parsed.items
      .map((item, i) => (item.quantity > 1 ? i : -1))
      .filter((i) => i !== -1);

    if (ambiguousIdx.length === 0) return parsed;

    // Cap at 10 ambiguous items (1024 combos) to avoid blowup
    if (ambiguousIdx.length > 10) return parsed;

    // Try all 2^N combinations of flip/no-flip for ambiguous items.
    // Start from the end (all-flipped) since consistent misinterpretation is most likely.
    const combos = 1 << ambiguousIdx.length;
    for (let mask = combos - 1; mask >= 1; mask--) {
      const candidateItems = parsed.items.map((item, i) => {
        const bit = ambiguousIdx.indexOf(i);
        if (bit !== -1 && mask & (1 << bit)) {
          return {
            ...item,
            totalPrice: item.unitPrice,
            unitPrice: Math.round(item.unitPrice / item.quantity),
          };
        }
        return item;
      });

      const candidateSum = candidateItems.reduce(
        (sum, item) => sum + item.totalPrice,
        0,
      );

      if (Math.abs(candidateSum - reference) <= tolerance) {
        return { ...parsed, items: candidateItems };
      }
    }

    // No combination matches — return original
    return parsed;
  }

  private async assertMember(tripId: number, userId: number): Promise<void> {
    const member = await this.prisma.tripMember.findUnique({
      where: { tripId_userId: { tripId, userId } },
    });

    if (!member || member.inviteStatus !== InviteStatus.ACCEPTED) {
      throw new ForbiddenException('You are not a member of this trip');
    }
  }
}
