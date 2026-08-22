#!/usr/bin/env node
/**
 * Prepares the devnet configuration the group wallet needs.
 *
 * Creates a fee payer keypair if there is not one already, funds it from the
 * devnet faucet, and prints the three environment variables to add. The secret
 * key is written to a gitignored file and never printed, so a shared terminal
 * or a pasted log cannot leak it.
 *
 *   node scripts/setup-solana-devnet.mjs
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';

import { Connection, Keypair, LAMPORTS_PER_SOL } from '@solana/web3.js';
import bs58 from 'bs58';

/** Circle's USDC on Solana devnet. The faucet at faucet.circle.com mints this. */
const DEVNET_USDC_MINT = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU';
const RPC_URL = 'https://api.devnet.solana.com';
const KEY_PATH = 'keys/solana-fee-payer.json';
/** Enough for vault creation, member sync and a long test session. */
const TARGET_SOL = 2;

function loadOrCreateKeypair() {
  if (existsSync(KEY_PATH)) {
    const secret = JSON.parse(readFileSync(KEY_PATH, 'utf8'));
    return { keypair: Keypair.fromSecretKey(Uint8Array.from(secret)), created: false };
  }
  mkdirSync('keys', { recursive: true });
  const keypair = Keypair.generate();
  writeFileSync(KEY_PATH, JSON.stringify([...keypair.secretKey]), { mode: 0o600 });
  return { keypair, created: true };
}

const { keypair, created } = loadOrCreateKeypair();
const connection = new Connection(RPC_URL, 'confirmed');

console.log(`fee payer: ${keypair.publicKey.toBase58()}`);
console.log(created ? 'created a new keypair' : `reusing ${KEY_PATH}`);

let balance = await connection.getBalance(keypair.publicKey);
console.log(`balance: ${(balance / LAMPORTS_PER_SOL).toFixed(3)} SOL`);

if (balance < TARGET_SOL * LAMPORTS_PER_SOL) {
  console.log('requesting an airdrop...');
  try {
    const signature = await connection.requestAirdrop(
      keypair.publicKey,
      TARGET_SOL * LAMPORTS_PER_SOL,
    );
    const { blockhash, lastValidBlockHeight } =
      await connection.getLatestBlockhash();
    await connection.confirmTransaction(
      { signature, blockhash, lastValidBlockHeight },
      'confirmed',
    );
    balance = await connection.getBalance(keypair.publicKey);
    console.log(`funded: ${(balance / LAMPORTS_PER_SOL).toFixed(3)} SOL`);
  } catch (error) {
    // The public devnet faucet is rate limited and refuses often. Not fatal:
    // the address is what matters and it can be funded by hand.
    console.log(`airdrop refused (${String(error).split('\n')[0]})`);
    console.log(`fund by hand at https://faucet.solana.com`);
  }
}

// Written straight into .env rather than printed. A secret key on stdout ends
// up in scrollback, screen shares and pasted logs.
const vars = {
  SOLANA_RPC_URL: RPC_URL,
  SOLANA_USDC_MINT: DEVNET_USDC_MINT,
  SOLANA_FEE_PAYER_SECRET_KEY: bs58.encode(keypair.secretKey),
};

let env = existsSync('.env') ? readFileSync('.env', 'utf8') : '';
const added = [];
const kept = [];
for (const [key, value] of Object.entries(vars)) {
  if (new RegExp(`^${key}=`, 'm').test(env)) {
    // Never overwrite: a key already there may be the one the deployed program
    // was created with, and replacing it would orphan every existing vault.
    kept.push(key);
    continue;
  }
  env += `${env.endsWith('\n') || env === '' ? '' : '\n'}${key}=${value}\n`;
  added.push(key);
}
writeFileSync('.env', env, { mode: 0o600 });

console.log(`\nadded to .env: ${added.join(', ') || 'nothing'}`);
if (kept.length > 0) {
  console.log(`left alone (already set): ${kept.join(', ')}`);
}
console.log('\nNext:');
console.log('  1. restart the server so it picks the new values up');
console.log('  2. get test USDC at https://faucet.circle.com (Solana Devnet)');
console.log('  3. send it to the address on the deposit screen');
