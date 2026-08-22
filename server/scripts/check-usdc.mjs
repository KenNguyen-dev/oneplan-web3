#!/usr/bin/env node
/**
 * Reports what a Solana devnet address holds, and how it got there.
 *
 * Written to answer "I sent USDC and it did not arrive": it distinguishes
 * between the address never receiving anything, receiving a different token,
 * and receiving the right token into an account the app is not reading.
 *
 *   node scripts/check-usdc.mjs <address>
 */
import { Connection, PublicKey } from '@solana/web3.js';

const CIRCLE_DEVNET_USDC = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU';
const TOKEN_PROGRAMS = [
  ['SPL Token', 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'],
  ['Token-2022', 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb'],
];

const input = process.argv[2];
if (!input) {
  console.error('usage: node scripts/check-usdc.mjs <address>');
  process.exit(1);
}

let owner;
try {
  owner = new PublicKey(input);
} catch {
  console.error(`"${input}" is not a valid Solana address`);
  process.exit(1);
}

const connection = new Connection('https://api.devnet.solana.com', 'confirmed');

const lamports = await connection.getBalance(owner);
console.log(`address : ${owner.toBase58()}`);
console.log(`SOL     : ${(lamports / 1e9).toFixed(4)}`);

let found = false;
for (const [label, programId] of TOKEN_PROGRAMS) {
  const accounts = await connection.getParsedTokenAccountsByOwner(owner, {
    programId: new PublicKey(programId),
  });
  for (const { pubkey, account } of accounts.value) {
    found = true;
    const info = account.data.parsed.info;
    const isUsdc = info.mint === CIRCLE_DEVNET_USDC;
    console.log(`\n${label} account ${pubkey.toBase58()}`);
    console.log(`  mint   : ${info.mint}${isUsdc ? '  (Circle devnet USDC)' : ''}`);
    console.log(`  amount : ${info.tokenAmount.uiAmountString}`);
  }
}
if (!found) {
  console.log('\nno token accounts at all — nothing has ever been sent here');
}

const signatures = await connection.getSignaturesForAddress(owner, { limit: 10 });
console.log(`\n${signatures.length} recent transaction(s)`);
for (const entry of signatures) {
  const when = entry.blockTime
    ? new Date(entry.blockTime * 1000).toISOString()
    : 'unknown time';
  console.log(`  ${when}  ${entry.err ? 'FAILED' : 'ok'}  ${entry.signature}`);
}
console.log(
  `\nexplorer: https://explorer.solana.com/address/${owner.toBase58()}?cluster=devnet`,
);
