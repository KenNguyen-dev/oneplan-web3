import { ConfigService } from '@nestjs/config';
import { Keypair, PublicKey } from '@solana/web3.js';
import { getAssociatedTokenAddressSync } from '@solana/spl-token';
import bs58 from 'bs58';
import { SolanaService } from './solana.service';

const PROGRAM_ID = '8pjmDZvmRzjcSwzffqnsdzsPRb3nV9BiVDhGU3vmR7uD';
const USDC_MINT = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU';

function configWith(overrides: Record<string, string> = {}): ConfigService {
  const values: Record<string, string> = {
    SOLANA_RPC_URL: 'https://api.devnet.solana.com',
    SOLANA_PROGRAM_ID: PROGRAM_ID,
    SOLANA_USDC_MINT: USDC_MINT,
    SOLANA_COMMITMENT: 'confirmed',
    SOLANA_FEE_PAYER_SECRET_KEY: bs58.encode(Keypair.generate().secretKey),
    ...overrides,
  };
  return {
    get: (k: string, d?: string) => values[k] ?? d,
    getOrThrow: (k: string) => {
      const v = values[k];
      if (v === undefined) throw new Error(`missing ${k}`);
      return v;
    },
  } as ConfigService;
}

describe('SolanaService', () => {
  it('reports configured when a fee payer key is present', () => {
    const service = new SolanaService(configWith());
    expect(service.isConfigured).toBe(true);
    expect(service.program.programId.toBase58()).toBe(PROGRAM_ID);
    expect(service.usdcMint.toBase58()).toBe(USDC_MINT);
  });

  it('reports unconfigured when the fee payer key is empty', () => {
    const service = new SolanaService(
      configWith({ SOLANA_FEE_PAYER_SECRET_KEY: '' }),
    );
    expect(service.isConfigured).toBe(false);
  });

  it('throws rather than signing when no fee payer is configured', () => {
    const service = new SolanaService(
      configWith({ SOLANA_FEE_PAYER_SECRET_KEY: '' }),
    );
    expect(() => service.feePayer).toThrow(/not configured/i);
  });

  it('derives the vault PDA the same way the program does', () => {
    const service = new SolanaService(configWith());
    const seed = Buffer.alloc(8);
    seed.writeBigUInt64LE(1001n);
    const [expected] = PublicKey.findProgramAddressSync(
      [Buffer.from('vault'), seed],
      new PublicKey(PROGRAM_ID),
    );
    expect(service.vaultPda(1001).toBase58()).toBe(expected.toBase58());
  });

  it('derives the treasury ATA from the fee payer by default', () => {
    const service = new SolanaService(configWith());
    const expected = getAssociatedTokenAddressSync(
      service.usdcMint,
      service.feePayer.publicKey,
    );
    expect(service.treasuryAta().toBase58()).toBe(expected.toBase58());
  });

  it('exposes cancelSpend among the program instructions', () => {
    const service = new SolanaService(configWith());
    expect(Object.keys(service.program.methods)).toContain('cancelSpend');
    expect(Object.keys(service.program.methods)).toContain('setMemberRole');
    expect(Object.keys(service.program.methods)).toContain('payoutLeave');
    expect(Object.keys(service.program.methods)).toHaveLength(14);
  });
});
