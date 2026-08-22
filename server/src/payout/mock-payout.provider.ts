import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import {
  PayoutInput,
  PayoutOutcome,
  PayoutProvider,
  PayoutResult,
  Quote,
  QuoteInput,
  RecipientInfo,
  RecipientInput,
} from './payout-provider.interface';
import { NAPAS_BANK_BINS } from '../trip-vault/vault-bank-names';

const MOCK_NAMES = [
  'NGUYEN VAN A',
  'TRAN THI B',
  'LE VAN C',
  'PHAM THI D',
  'HOANG VAN E',
];

/** Fixed rate so quotes are deterministic in tests. */
const VND_PER_USDC = 26_500n;
/** 0.75%, expressed in basis points. */
const FEE_BPS = 75n;

/**
 * Bank accounts are digits; MoMo wallet VietQR uses BVBank virtual accounts
 * like `99MM24011M34875080` — alphanumeric, longer than a typical account.
 */
const ACCOUNT_NUMBER_RE = /^[0-9A-Za-z]{4,32}$/;

interface MockRecord {
  outcome: PayoutOutcome;
  eventualOutcome: PayoutOutcome;
}

/**
 * Stands in for the fiat leg during phase 1. The on-chain half of a payment is
 * real; only this is simulated.
 *
 * `MOCK_PAYOUT_OUTCOME` drives behaviour so the reconciliation paths are all
 * reachable in tests and in a live demo:
 *
 * - `success` - resolves immediately
 * - `failed`  - a confirmed failure, the only case that may trigger a revert
 * - `timeout` - returns UNKNOWN, then resolves to SUCCESS on the next status
 *               check. This is the case that punishes an eager revert
 * - `unknown` - never resolves, exercising the alert path
 */
@Injectable()
export class MockPayoutProvider implements PayoutProvider {
  readonly name = 'mock';
  private readonly logger = new Logger(MockPayoutProvider.name);
  private readonly records = new Map<string, MockRecord>();
  private readonly configured: string;

  constructor(private readonly config: ConfigService) {
    this.configured = this.config.get<string>('MOCK_PAYOUT_OUTCOME', 'success');
  }

  async validateRecipient(
    input: RecipientInput,
  ): Promise<RecipientInfo | null> {
    if (!NAPAS_BANK_BINS.has(input.bankBin)) {
      return Promise.resolve(null);
    }
    if (!ACCOUNT_NUMBER_RE.test(input.accountNumber)) {
      return Promise.resolve(null);
    }
    // MoMo personal receive codes settle via BVBank VANs prefixed `99MM`.
    if (/^99MM/i.test(input.accountNumber)) {
      return Promise.resolve({ accountName: 'MOMO WALLET' });
    }
    // Deterministic so a given account always shows the same name.
    const index =
      [...input.accountNumber].reduce((sum, ch) => sum + ch.charCodeAt(0), 0) %
      MOCK_NAMES.length;
    return Promise.resolve({ accountName: MOCK_NAMES[index] });
  }

  quote(input: QuoteInput): Promise<Quote> {
    const grossMicro = (input.amountVnd * 1_000_000n) / VND_PER_USDC;
    const feeMicro = (grossMicro * FEE_BPS) / 10_000n;
    return Promise.resolve({
      amountUsdcMicro: grossMicro,
      feeMicro,
      rate: VND_PER_USDC.toString(),
    });
  }

  payout(input: PayoutInput): Promise<PayoutResult> {
    const existing = this.records.get(input.reference);
    if (existing) {
      // Idempotent: a retry reports the original result without re-sending.
      return Promise.resolve(this.toResult(existing.outcome, input.reference));
    }

    const record = this.recordFor();
    this.records.set(input.reference, record);
    this.logger.log(
      `mock payout ${input.reference}: ${input.amountVnd} VND to ` +
        `${input.bankBin}/${input.accountNumber} -> ${record.outcome}`,
    );
    return Promise.resolve(this.toResult(record.outcome, input.reference));
  }

  getStatus(reference: string): Promise<PayoutOutcome> {
    return Promise.resolve(
      this.records.get(reference)?.eventualOutcome ?? 'UNKNOWN',
    );
  }

  /** Test helper: how many times a reference was actually sent. */
  callCount(reference: string): number {
    return this.records.has(reference) ? 1 : 0;
  }

  private recordFor(): MockRecord {
    switch (this.configured) {
      case 'failed':
        return { outcome: 'FAILED', eventualOutcome: 'FAILED' };
      case 'timeout':
        return { outcome: 'UNKNOWN', eventualOutcome: 'SUCCESS' };
      case 'unknown':
        return { outcome: 'UNKNOWN', eventualOutcome: 'UNKNOWN' };
      default:
        return { outcome: 'SUCCESS', eventualOutcome: 'SUCCESS' };
    }
  }

  private toResult(outcome: PayoutOutcome, reference: string): PayoutResult {
    if (outcome === 'FAILED') {
      return {
        outcome,
        failureCode: 'MOCK_DECLINED',
        providerReference: reference,
      };
    }
    return { outcome, providerReference: reference };
  }
}
