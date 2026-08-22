export const PAYOUT_PROVIDER = Symbol('PAYOUT_PROVIDER');

export type PayoutOutcome = 'SUCCESS' | 'FAILED' | 'PENDING' | 'UNKNOWN';

export interface RecipientInput {
  bankBin: string;
  accountNumber: string;
}

export interface RecipientInfo {
  accountName: string;
}

export interface QuoteInput {
  amountVnd: bigint;
}

export interface Quote {
  amountUsdcMicro: bigint;
  feeMicro: bigint;
  /** VND per USDC, as a decimal string so no precision is lost in transit. */
  rate: string;
}

export interface PayoutInput extends RecipientInput {
  amountVnd: bigint;
  /** Deterministic idempotency key. Maps to FinFan's mandatory X-Request-ID. */
  reference: string;
  description?: string;
}

export interface PayoutResult {
  outcome: PayoutOutcome;
  failureCode?: string;
  providerReference?: string;
}

/**
 * A fiat payout rail. The method set deliberately mirrors FinFan's API
 * (InterbankTransfer/validate, Resources/FXRates, InterbankTransfer/load, plus a
 * status query) so that a real provider drops in without touching callers.
 *
 * Implementations must be idempotent on `reference`: the reconciliation cron
 * retries, and a duplicate call must never move money twice.
 */
export interface PayoutProvider {
  readonly name: string;
  validateRecipient(input: RecipientInput): Promise<RecipientInfo | null>;
  quote(input: QuoteInput): Promise<Quote>;
  payout(input: PayoutInput): Promise<PayoutResult>;
  getStatus(reference: string): Promise<PayoutOutcome>;
}
