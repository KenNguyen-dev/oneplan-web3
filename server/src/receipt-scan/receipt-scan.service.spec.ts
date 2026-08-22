import {
  GatewayTimeoutException,
  BadGatewayException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InviteStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { GeminiService } from '../common/gemini/gemini.service';
import { ReceiptScanService } from './receipt-scan.service';
import { ReceiptScanResultDto } from './dto/receipt-scan-result.dto';

describe('ReceiptScanService', () => {
  let service: ReceiptScanService;
  let generateJson: jest.Mock;
  let prisma: PrismaService;

  beforeEach(() => {
    generateJson = jest.fn();
    prisma = {
      tripMember: {
        findUnique: jest
          .fn()
          .mockResolvedValue({ inviteStatus: InviteStatus.ACCEPTED }),
      },
    } as unknown as PrismaService;
    service = new ReceiptScanService(
      prisma,
      { track: jest.fn() } as any,
      { generateJson } as unknown as GeminiService,
    );
  });

  // Helper to call private method
  const validate = (parsed: ReceiptScanResultDto) =>
    (service as any).validateAndCorrectPrices(parsed);

  describe('scanReceipt (Gemini path)', () => {
    const img = Buffer.from('receipt-bytes');

    it('returns the parsed result and tracks BILL_SCANNED', async () => {
      const track = jest.fn();
      (service as any).analytics = { track };
      generateJson.mockResolvedValue({
        items: [
          { name: 'Pho', quantity: 1, unitPrice: 50000, totalPrice: 50000 },
        ],
        currency: 'VND',
      });

      const result = await service.scanReceipt(1, 2, img, 'image/jpeg');

      expect(result.items).toHaveLength(1);
      expect(generateJson).toHaveBeenCalledWith(
        expect.objectContaining({ imageBytes: img, mimeType: 'image/jpeg' }),
      );
      expect(track).toHaveBeenCalled();
    });

    it('maps an aborted (timed-out) request to GatewayTimeoutException', async () => {
      generateJson.mockRejectedValue(
        Object.assign(new Error('aborted'), { name: 'AbortError' }),
      );
      await expect(
        service.scanReceipt(1, 2, img, 'image/jpeg'),
      ).rejects.toBeInstanceOf(GatewayTimeoutException);
    });

    it('rethrows a BadGatewayException from Gemini unchanged', async () => {
      generateJson.mockRejectedValue(new BadGatewayException('vertex down'));
      await expect(
        service.scanReceipt(1, 2, img, 'image/jpeg'),
      ).rejects.toBeInstanceOf(BadGatewayException);
    });

    it('throws UnprocessableEntityException when no items are detected', async () => {
      generateJson.mockResolvedValue({ items: [] });
      await expect(
        service.scanReceipt(1, 2, img, 'image/jpeg'),
      ).rejects.toBeInstanceOf(UnprocessableEntityException);
    });
  });

  describe('validateAndCorrectPrices', () => {
    it('returns original when items sum matches subtotal', () => {
      const parsed: ReceiptScanResultDto = {
        items: [
          { name: 'Ramen', quantity: 2, unitPrice: 10000, totalPrice: 20000 },
          { name: 'Tea', quantity: 1, unitPrice: 5000, totalPrice: 5000 },
        ],
        subtotal: 25000,
        total: 27500,
        currency: 'VND',
      };

      const result = validate(parsed);
      expect(result).toBe(parsed);
    });

    it('corrects prices when AI misinterprets line totals as unit prices', () => {
      // AI saw "Ramen 2 20000" and thought unitPrice=20000, totalPrice=40000
      // but the receipt meant: 2 ramens totaling 20000
      const parsed: ReceiptScanResultDto = {
        items: [
          { name: 'Ramen', quantity: 2, unitPrice: 20000, totalPrice: 40000 },
          { name: 'Tea', quantity: 1, unitPrice: 5000, totalPrice: 5000 },
        ],
        subtotal: 25000,
        total: 27500,
        currency: 'VND',
      };

      const result = validate(parsed);
      expect(result.items[0].totalPrice).toBe(20000);
      expect(result.items[0].unitPrice).toBe(10000);
      // Single-quantity item unchanged
      expect(result.items[1]).toEqual(parsed.items[1]);
    });

    it('returns original when sum overshoots but correction does not fix it', () => {
      const parsed: ReceiptScanResultDto = {
        items: [
          { name: 'Ramen', quantity: 2, unitPrice: 20000, totalPrice: 40000 },
          { name: 'Sushi', quantity: 3, unitPrice: 15000, totalPrice: 45000 },
        ],
        subtotal: 50000, // neither 85000 nor corrected sum (35000) matches
        currency: 'VND',
      };

      const result = validate(parsed);
      expect(result).toBe(parsed);
    });

    it('returns original when no subtotal or total available', () => {
      const parsed: ReceiptScanResultDto = {
        items: [
          { name: 'Ramen', quantity: 2, unitPrice: 20000, totalPrice: 40000 },
        ],
        currency: 'VND',
      };

      const result = validate(parsed);
      expect(result).toBe(parsed);
    });

    it('returns original when sum is less than reference (missing items)', () => {
      const parsed: ReceiptScanResultDto = {
        items: [
          { name: 'Ramen', quantity: 1, unitPrice: 10000, totalPrice: 10000 },
        ],
        subtotal: 50000, // items sum way under — likely missing items
        currency: 'VND',
      };

      const result = validate(parsed);
      expect(result).toBe(parsed);
    });

    it('falls back to total when subtotal is not available', () => {
      const parsed: ReceiptScanResultDto = {
        items: [
          { name: 'Ramen', quantity: 2, unitPrice: 20000, totalPrice: 40000 },
          { name: 'Tea', quantity: 1, unitPrice: 5000, totalPrice: 5000 },
        ],
        total: 25000, // no subtotal, use total
        currency: 'VND',
      };

      const result = validate(parsed);
      expect(result.items[0].totalPrice).toBe(20000);
      expect(result.items[0].unitPrice).toBe(10000);
    });

    it('corrects only the misinterpreted item when AI is inconsistent', () => {
      // AI got Beer right (unitPrice=15k, totalPrice=45k)
      // but got Ramen wrong (treated 124k line total as unit price)
      const parsed: ReceiptScanResultDto = {
        items: [
          { name: 'Ramen', quantity: 2, unitPrice: 124000, totalPrice: 248000 },
          { name: 'Beer', quantity: 3, unitPrice: 15000, totalPrice: 45000 },
          {
            name: 'Spring Roll',
            quantity: 1,
            unitPrice: 30000,
            totalPrice: 30000,
          },
        ],
        subtotal: 199000,
        currency: 'VND',
      };

      const result = validate(parsed);
      // Ramen corrected: totalPrice=124k (line total), unitPrice=62k
      expect(result.items[0].totalPrice).toBe(124000);
      expect(result.items[0].unitPrice).toBe(62000);
      // Beer untouched — was already correct
      expect(result.items[1].totalPrice).toBe(45000);
      expect(result.items[1].unitPrice).toBe(15000);
      // Spring Roll untouched (qty=1)
      expect(result.items[2]).toEqual(parsed.items[2]);
    });

    it('tolerates small rounding differences (within 2%)', () => {
      const parsed: ReceiptScanResultDto = {
        items: [
          { name: 'Ramen', quantity: 1, unitPrice: 25100, totalPrice: 25100 },
        ],
        subtotal: 25000, // 0.4% off — within tolerance
        currency: 'VND',
      };

      const result = validate(parsed);
      expect(result).toBe(parsed);
    });
  });
});
