import * as Joi from 'joi';
import { solanaConfigSchema } from './solana.config';

describe('solanaConfigSchema', () => {
  const valid = {
    SOLANA_RPC_URL: 'https://api.devnet.solana.com',
    SOLANA_PROGRAM_ID: '8pjmDZvmRzjcSwzffqnsdzsPRb3nV9BiVDhGU3vmR7uD',
    SOLANA_USDC_MINT: '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
    SOLANA_COMMITMENT: 'confirmed',
    SOLANA_FEE_PAYER_SECRET_KEY: '',
    SOLANA_RECEIVER_SECRET_KEY: '',
    MOCK_PAYOUT_OUTCOME: 'success',
  };

  const validate = (overrides: Record<string, unknown> = {}) =>
    Joi.object(solanaConfigSchema).validate(
      { ...valid, ...overrides },
      { allowUnknown: true },
    );

  it('accepts the documented defaults', () => {
    expect(validate().error).toBeUndefined();
  });

  it('applies defaults when the vars are absent', () => {
    const result = Joi.object(solanaConfigSchema).validate(
      {},
      { allowUnknown: true },
    );
    const error = result.error;
    const value = result.value as Record<string, string>;
    expect(error).toBeUndefined();
    expect(value.SOLANA_COMMITMENT).toBe('confirmed');
    expect(value.MOCK_PAYOUT_OUTCOME).toBe('success');
  });

  it('rejects a non-https RPC url', () => {
    expect(validate({ SOLANA_RPC_URL: 'not-a-url' }).error).toBeDefined();
  });

  it('rejects an unknown mock outcome', () => {
    expect(validate({ MOCK_PAYOUT_OUTCOME: 'explode' }).error).toBeDefined();
  });

  it('allows an empty fee payer key so the server still boots', () => {
    expect(validate({ SOLANA_FEE_PAYER_SECRET_KEY: '' }).error).toBeUndefined();
  });
});
