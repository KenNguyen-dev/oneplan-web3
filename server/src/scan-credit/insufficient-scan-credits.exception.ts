import { HttpException, HttpStatus } from '@nestjs/common';

export interface InsufficientScanCreditsPayload {
  available: number;
  nextProGrantAt: Date | null;
  canPurchase: boolean;
}

// Thrown by ScanCreditService.consume when the user has no available scan
// credits. Status 402 Payment Required — the "existing insufficient-quota
// behavior" the iOS client already handles for the old quota system.
export class InsufficientScanCreditsException extends HttpException {
  constructor(payload: InsufficientScanCreditsPayload) {
    super(
      {
        code: 'insufficient_scan_credits',
        message: "You're out of scan credits.",
        available: payload.available,
        nextProGrantAt: payload.nextProGrantAt
          ? payload.nextProGrantAt.toISOString()
          : null,
        canPurchase: payload.canPurchase,
      },
      HttpStatus.PAYMENT_REQUIRED,
    );
  }
}
