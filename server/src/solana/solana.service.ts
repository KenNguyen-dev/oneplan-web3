import {
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AnchorProvider, Program, Wallet } from '@coral-xyz/anchor';
import BN from 'bn.js';
import {
  createAssociatedTokenAccountIdempotentInstruction,
  getAssociatedTokenAddressSync,
} from '@solana/spl-token';
import {
  Commitment,
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
} from '@solana/web3.js';
import bs58 from 'bs58';

import idl from './idl/oneplan_vault.json';
import type { OneplanVault } from './types/oneplan_vault';

const VAULT_SEED = Buffer.from('vault');

function u64le(value: number | bigint): Buffer {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64LE(BigInt(value));
  return buf;
}

/// A blockhash is valid for 150 blocks. Used to bound the confirmation wait
/// when the transaction's own blockhash is what we are confirming against.
const BLOCKHASH_VALIDITY_BLOCKS = 150;

@Injectable()
export class SolanaService {
  private readonly logger = new Logger(SolanaService.name);
  readonly connection: Connection;
  readonly program: Program<OneplanVault>;
  readonly usdcMint: PublicKey;
  private readonly keypair: Keypair | null;

  constructor(private readonly config: ConfigService) {
    const rpcUrl = this.config.get<string>(
      'SOLANA_RPC_URL',
      'https://api.devnet.solana.com',
    );
    const commitment = this.config.get<Commitment>(
      'SOLANA_COMMITMENT',
      'confirmed',
    );
    // Host only: the endpoint carries an API key and a log line is the easiest
    // place for one to leak.
    new Logger(SolanaService.name).log(`RPC ${new URL(rpcUrl).host}`);
    // The websocket endpoint is given rather than derived. web3.js builds one
    // from the http url by swapping the scheme, which drops the query string —
    // and the api key lives there. The subscription was refused, every
    // confirmation fell back to polling, and one confirmation became hundreds of
    // requests until the provider rate-limited everything else the app needed.
    this.connection = new Connection(rpcUrl, {
      commitment,
      wsEndpoint: SolanaService.websocketFor(rpcUrl),
    });
    this.usdcMint = new PublicKey(
      this.config.getOrThrow<string>('SOLANA_USDC_MINT'),
    );

    const secret = this.config.get<string>('SOLANA_FEE_PAYER_SECRET_KEY', '');
    this.keypair = secret ? Keypair.fromSecretKey(bs58.decode(secret)) : null;

    // A throwaway wallet keeps Anchor constructible when no fee payer is set.
    // Every write path checks isConfigured first, so it is never used to sign.
    const wallet = new Wallet(this.keypair ?? Keypair.generate());
    const provider = new AnchorProvider(this.connection, wallet, {
      commitment,
    });
    this.program = new Program(idl as OneplanVault, provider);

    if (!this.keypair) {
      this.logger.warn(
        'SOLANA_FEE_PAYER_SECRET_KEY is not set - vault endpoints will return 503',
      );
    }
  }

  get isConfigured(): boolean {
    return this.keypair !== null;
  }

  get feePayer(): Keypair {
    if (!this.keypair) {
      throw new ServiceUnavailableException(
        'Solana fee payer is not configured on this server',
      );
    }
    return this.keypair;
  }

  vaultPda(tripId: number): PublicKey {
    return PublicKey.findProgramAddressSync(
      [VAULT_SEED, u64le(tripId)],
      this.program.programId,
    )[0];
  }

  /**
   * USDC ATA that receives the 0.1% deposit skim.
   *
   * Defaults to the fee payer's ATA. Override with SOLANA_TREASURY_OWNER when
   * ops wants a dedicated treasury wallet.
   */
  treasuryAta(): PublicKey {
    return getAssociatedTokenAddressSync(this.usdcMint, this.treasuryOwner());
  }

  /** Owner of the treasury USDC ATA (fee payer unless SOLANA_TREASURY_OWNER). */
  treasuryOwner(): PublicKey {
    const owner = this.config.get<string>('SOLANA_TREASURY_OWNER', '');
    return owner ? new PublicKey(owner) : this.feePayer.publicKey;
  }

  /**
   * Creates the treasury USDC ATA if it is missing.
   *
   * Deposit skim CPI requires a live token account. Without this, the first
   * deposit after a fresh fee-payer wallet fails on chain with no DB row, and
   * the app looks like the button did nothing. Kept as its own fee-payer tx so
   * the member-signed deposit stays a single instruction the client can verify.
   */
  async ensureTreasuryAta(): Promise<PublicKey> {
    const ata = this.treasuryAta();
    const info = await this.connection.getAccountInfo(ata);
    if (info) {
      return ata;
    }

    const ix = createAssociatedTokenAccountIdempotentInstruction(
      this.feePayer.publicKey,
      ata,
      this.treasuryOwner(),
      this.usdcMint,
    );
    const signature = await this.sendAsFeePayer([ix]);
    this.logger.log(`created treasury USDC ATA ${ata.toBase58()}: ${signature}`);
    return ata;
  }

  /**
   * Builds a legacy transaction, signs it as fee payer, and returns it base64
   * encoded for the client to add its own signature. Legacy only: the iOS client
   * verifies the transaction before signing and does not handle v0 lookup tables.
   */
  async buildUnsignedTx(ixs: TransactionInstruction[]): Promise<string> {
    const { blockhash } = await this.connection.getLatestBlockhash();
    const tx = new Transaction();
    tx.add(...ixs);
    tx.feePayer = this.feePayer.publicKey;
    tx.recentBlockhash = blockhash;
    tx.partialSign(this.feePayer);
    return tx
      .serialize({ requireAllSignatures: false, verifySignatures: false })
      .toString('base64');
  }

  /**
   * Broadcasts a transaction the client has finished signing, and returns as
   * soon as the chain has taken it.
   *
   * Deliberately does not wait for confirmation. Broadcasting and confirming
   * are two separate calls, and losing the second used to lose the signature
   * with it — leaving no way to ask afterwards whether the transaction had
   * landed. The caller records the signature first and confirms second, so a
   * lost answer stays a question that can still be asked.
   */
  async broadcastSigned(base64Tx: string): Promise<string> {
    const tx = Transaction.from(Buffer.from(base64Tx, 'base64'));
    return this.connection.sendRawTransaction(tx.serialize());
  }

  /**
   * Waits for a broadcast transaction to confirm.
   *
   * The expiry window comes from the blockhash the transaction was built with,
   * not a fresh one: a newer blockhash describes a later window than the one
   * this transaction actually lives in, which can report it expired while it is
   * still perfectly valid.
   */
  async confirmSigned(base64Tx: string, signature: string): Promise<void> {
    const tx = Transaction.from(Buffer.from(base64Tx, 'base64'));
    const blockhash = tx.recentBlockhash;
    if (!blockhash) {
      // Nothing to bound the wait with, so ask the chain outright instead.
      await this.connection.confirmTransaction(signature, 'confirmed');
      return;
    }
    const lastValidBlockHeight =
      (await this.connection.getBlockHeight('confirmed')) +
      BLOCKHASH_VALIDITY_BLOCKS;
    await this.connection.confirmTransaction(
      { signature, blockhash, lastValidBlockHeight },
      'confirmed',
    );
  }

  /**
   * Whether a signature reached the chain, and whether it succeeded there.
   *
   * This is what makes a lost answer recoverable: the question "did the thing
   * I sent actually happen" has one answer, and it is on chain.
   */
  async signatureLanded(signature: string): Promise<boolean> {
    const status = await this.connection.getSignatureStatus(signature, {
      searchTransactionHistory: true,
    });
    const value = status.value;
    return !!value && !value.err;
  }

  /** Sends a transaction that only the server needs to sign. */
  async sendAsFeePayer(
    ixs: TransactionInstruction[],
    extraSigners: Keypair[] = [],
  ): Promise<string> {
    const { blockhash, lastValidBlockHeight } =
      await this.connection.getLatestBlockhash();
    const tx = new Transaction();
    tx.add(...ixs);
    tx.feePayer = this.feePayer.publicKey;
    tx.recentBlockhash = blockhash;
    tx.sign(this.feePayer, ...extraSigners);
    const signature = await this.connection.sendRawTransaction(tx.serialize());
    await this.connection.confirmTransaction(
      { signature, blockhash, lastValidBlockHeight },
      'confirmed',
    );
    return signature;
  }

  private receiverKeypair: Keypair | null = null;

  /**
   * Owner of the wallet that receives USDC on a merchant payment. In phase 1 the
   * server controls it, standing exactly where Triple-A or FinFan will sit once
   * the fiat leg is real.
   */
  get receiverPublicKey(): PublicKey {
    return this.receiverKeypairOrThrow.publicKey;
  }

  get receiverKeypairOrThrow(): Keypair {
    if (!this.receiverKeypair) {
      const secret = this.config.get<string>('SOLANA_RECEIVER_SECRET_KEY', '');
      if (!secret) {
        throw new ServiceUnavailableException(
          'SOLANA_RECEIVER_SECRET_KEY is not configured',
        );
      }
      this.receiverKeypair = Keypair.fromSecretKey(bs58.decode(secret));
    }
    return this.receiverKeypair;
  }

  /**
   * Returns funds from the receiver wallet to a vault after a confirmed payout
   * failure. Both the server and the receiver sign; the server owns both keys in
   * phase 1.
   */
  async revertSpend(vaultPda: PublicKey, amountMicro: bigint): Promise<string> {
    const receiver = this.receiverKeypairOrThrow;
    const receiverAta = getAssociatedTokenAddressSync(
      this.usdcMint,
      receiver.publicKey,
    );
    const ix = await this.program.methods
      .revertSpend(new BN(amountMicro.toString()))
      .accountsPartial({
        vault: vaultPda,
        receiverAta,
        receiver: receiver.publicKey,
        server: this.feePayer.publicKey,
        usdcMint: this.usdcMint,
      })
      .instruction();
    return this.sendAsFeePayer([ix], [receiver]);
  }

  /**
   * After settlement empties the vault ATA and sets status Closed, reclaim
   * PDA + ATA rent to the fee payer. Safe to call only when ATA balance is 0.
   */
  async closeVault(vaultPda: PublicKey): Promise<string> {
    const vaultAta = getAssociatedTokenAddressSync(this.usdcMint, vaultPda, true);
    const ix = await this.program.methods
      .closeVault()
      .accountsPartial({
        vault: vaultPda,
        vaultAta,
        server: this.feePayer.publicKey,
      })
      .instruction();
    return this.sendAsFeePayer([ix]);
  }

  /** The same endpoint over websocket, api key and all. */
  private static websocketFor(rpcUrl: string): string {
    const url = new URL(rpcUrl);
    url.protocol = url.protocol === 'http:' ? 'ws:' : 'wss:';
    return url.toString();
  }

  async getTokenBalance(ata: PublicKey): Promise<bigint> {
    const info = await this.connection.getTokenAccountBalance(ata);
    return BigInt(info.value.amount);
  }
}
