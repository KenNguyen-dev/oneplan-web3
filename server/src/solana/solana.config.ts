import * as Joi from 'joi';

/**
 * Solana settings. Every one is optional with a working devnet default so the
 * server still boots without them; the vault endpoints check at request time
 * whether a fee payer is configured and return 503 if not.
 */
export const solanaConfigSchema = {
  SOLANA_RPC_URL: Joi.string()
    .uri({ scheme: ['http', 'https'] })
    .default('https://api.devnet.solana.com'),
  SOLANA_PROGRAM_ID: Joi.string()
    .min(32)
    .default('8pjmDZvmRzjcSwzffqnsdzsPRb3nV9BiVDhGU3vmR7uD'),
  SOLANA_USDC_MINT: Joi.string()
    .min(32)
    .default('4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU'),
  SOLANA_COMMITMENT: Joi.string()
    .valid('processed', 'confirmed', 'finalized')
    .default('confirmed'),
  SOLANA_FEE_PAYER_SECRET_KEY: Joi.string().allow('').default(''),
  SOLANA_RECEIVER_SECRET_KEY: Joi.string().allow('').default(''),
  /** Owner of the USDC ATA that receives the 0.1% deposit skim. Empty = fee payer. */
  SOLANA_TREASURY_OWNER: Joi.string().allow('').default(''),
  MOCK_PAYOUT_OUTCOME: Joi.string()
    .valid('success', 'failed', 'timeout', 'unknown')
    .default('success'),
};
