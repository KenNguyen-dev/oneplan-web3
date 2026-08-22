import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  InviteStatus,
  TripMemberRole,
  TripVault,
  VaultStatus,
  VaultTxKind,
  VaultTxStatus,
  WalletAccount,
} from '@prisma/client';
import { getAssociatedTokenAddressSync } from '@solana/spl-token';
import { PublicKey } from '@solana/web3.js';
import BN from 'bn.js';

import { PrismaService } from '../prisma/prisma.service';
import { TripsHandler } from '../realtime/handlers/trips.handler';
import { SolanaService } from '../solana/solana.service';

function toPublicKey(value: string, field: string): PublicKey {
  try {
    return new PublicKey(value);
  } catch {
    throw new BadRequestException(`${field} is not a valid Solana public key`);
  }
}

/// How long a vault balance is served without asking the chain again.
///
/// Every member's device polls this, so one trip of three was three reads of
/// the same account, and the public devnet endpoint rate-limits per IP — which
/// is what made a phone show itself as offline while holding a stale number.
/// Short enough that a balance is never meaningfully old, and every path that
/// moves money clears it anyway.
const BALANCE_CACHE_MS = 15_000;

/// Matches the program's own threshold. Below it the chain lets any active
/// member approve, and the app has to agree or it offers a button that fails.
const MIN_APPROVERS_TO_RESTRICT = 2;

@Injectable()
export class TripVaultService {
  private readonly balanceCache = new Map<
    number,
    { balanceMicro: bigint; expiresAt: number }
  >();

  private readonly logger = new Logger(TripVaultService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly solana: SolanaService,
    private readonly trips: TripsHandler,
  ) {}

  private assertConfigured(): void {
    if (!this.solana.isConfigured) {
      throw new ServiceUnavailableException(
        'Solana is not configured on this server',
      );
    }
  }

  async requireVault(tripId: number): Promise<TripVault> {
    const vault = await this.prisma.tripVault.findUnique({ where: { tripId } });
    if (!vault) {
      throw new NotFoundException(`Trip ${tripId} has no vault`);
    }
    return vault;
  }

  async linkWallet(userId: number, publicKey: string): Promise<WalletAccount> {
    const key = toPublicKey(publicKey, 'publicKey');
    return this.prisma.walletAccount.upsert({
      where: { userId },
      create: { userId, publicKey: key.toBase58() },
      update: { publicKey: key.toBase58() },
    });
  }

  /**
   * The caller's own wallet: where they hold USDC before contributing it.
   *
   * Money has to pass through here to reach the vault, because the deposit
   * instruction is what records who contributed. A transfer straight into the
   * vault from an exchange has no attributable sender, and settlement is built
   * on knowing who put in what.
   */
  async walletBalance(
    userId: number,
  ): Promise<{
    publicKey: string | null;
    usdcAta: string | null;
    balanceMicro: bigint;
  }> {
    const wallet = await this.prisma.walletAccount.findUnique({
      where: { userId },
    });
    if (!wallet) {
      return { publicKey: null, usdcAta: null, balanceMicro: 0n };
    }
    const owner = new PublicKey(wallet.publicKey);
    const ata = getAssociatedTokenAddressSync(this.solana.usdcMint, owner);
    try {
      return {
        publicKey: wallet.publicKey,
        usdcAta: ata.toBase58(),
        balanceMicro: await this.solana.getTokenBalance(ata),
      };
    } catch {
      // No token account yet, which is what a wallet that has never held USDC
      // looks like. Zero is the honest answer, not an error.
      return {
        publicKey: wallet.publicKey,
        usdcAta: ata.toBase58(),
        balanceMicro: 0n,
      };
    }
  }

  async createVault(
    tripId: number,
    // Retained for the call site's clarity and future auditing; the on-chain
    // authority is the server, so it does not affect what is created.
    userId: number,
    thresholdMicro: bigint,
    dailyLimitMicro: bigint,
  ): Promise<TripVault> {
    this.assertConfigured();

    if (thresholdMicro <= 0n || dailyLimitMicro < thresholdMicro) {
      throw new BadRequestException(
        'thresholdMicro must be positive and dailyLimitMicro must be at least thresholdMicro',
      );
    }

    const existing = await this.prisma.tripVault.findUnique({
      where: { tripId },
    });
    if (existing) {
      return existing;
    }

    // No wallet check: the vault authority is the server fee payer, not the
    // creator, so requiring a linked wallet here blocked trip creation for
    // nothing. Members link a wallet when they first open the vault, and
    // syncMembers only adds the ones that have.
    const vaultPda = this.solana.vaultPda(tripId);
    const usdcAta = getAssociatedTokenAddressSync(
      this.solana.usdcMint,
      vaultPda,
      true,
    );

    // Phase 1 keeps vault creation server-driven, so the fee payer is recorded as
    // the on-chain authority. Once the client can co-sign, pass the trip
    // creator's key here instead.
    const ix = await this.solana.program.methods
      .initVault(
        new BN(tripId),
        new BN(thresholdMicro.toString()),
        new BN(dailyLimitMicro.toString()),
      )
      .accounts({
        usdcMint: this.solana.usdcMint,
        authority: this.solana.feePayer.publicKey,
        server: this.solana.feePayer.publicKey,
      })
      .instruction();

    const signature = await this.solana.sendAsFeePayer([ix]);
    this.logger.log(`init_vault for trip ${tripId}: ${signature}`);

    // Same window as init: deposit skim needs a live treasury ATA, and creating
    // it here means the first deposit is not the first time it is noticed missing.
    await this.solana.ensureTreasuryAta();

    return this.prisma.tripVault.create({
      data: {
        tripId,
        vaultPda: vaultPda.toBase58(),
        usdcAta: usdcAta.toBase58(),
        thresholdMicro,
        dailyLimitMicro,
      },
    });
  }

  /**
   * Adds every accepted trip member that has a linked wallet but is not yet in
   * the vault's on-chain member table. Safe to call repeatedly.
   */
  async syncMembers(tripId: number): Promise<number> {
    this.assertConfigured();
    const vault = await this.requireVault(tripId);
    const vaultPda = new PublicKey(vault.vaultPda);

    const members = await this.prisma.tripMember.findMany({
      where: { tripId, inviteStatus: InviteStatus.ACCEPTED },
      select: { userId: true },
    });
    const wallets = await this.prisma.walletAccount.findMany({
      where: { userId: { in: members.map((m) => m.userId) } },
    });

    const onChain = await this.solana.program.account.tripVault.fetch(vaultPda);
    const known = new Set(
      (onChain.members as { owner: PublicKey; active: boolean }[])
        .filter((m) => m.active)
        .map((m) => m.owner.toBase58()),
    );

    let added = 0;
    for (const wallet of wallets) {
      if (known.has(wallet.publicKey)) {
        continue;
      }

      const owner = new PublicKey(wallet.publicKey);
      const ix = await this.solana.program.methods
        .addMember()
        .accountsPartial({
          vault: vaultPda,
          owner,
          authority: this.solana.feePayer.publicKey,
        })
        .instruction();
      await this.solana.sendAsFeePayer([ix]);
      added += 1;
    }

    if (added > 0) {
      this.logger.log(`synced ${added} member(s) for trip ${tripId}`);
    }
    return added;
  }

  /**
   * Records on chain whether a member may approve an above-threshold spend.
   *
   * The chain keeps one bit; the app keeps the difference between host and
   * co-host. Best effort by design: a trip whose vault is not reachable still
   * has to be able to name its co-host, and the next sync will carry the
   * decision across.
   */
  async setMemberRole(
    tripId: number,
    userId: number,
    canApprove: boolean,
  ): Promise<void> {
    this.assertConfigured();
    const vault = await this.requireVault(tripId);
    const wallet = await this.prisma.walletAccount.findUnique({
      where: { userId },
    });
    if (!wallet) {
      return;
    }

    const vaultPda = new PublicKey(vault.vaultPda);
    const owner = new PublicKey(wallet.publicKey);
    const onChain = await this.solana.program.account.tripVault.fetch(vaultPda);
    const seated = (onChain.members as { owner: PublicKey }[]).some((m) =>
      m.owner.equals(owner),
    );
    if (!seated) {
      return;
    }

    const ix = await this.solana.program.methods
      .setMemberRole(canApprove ? 1 : 0)
      .accountsPartial({
        vault: vaultPda,
        owner,
        server: this.solana.feePayer.publicKey,
      })
      .instruction();
    await this.solana.sendAsFeePayer([ix]);
  }

  /**
   * Pushes every approver the app knows about onto the chain.
   *
   * Called after a member links a wallet, which is the first moment their
   * Member account exists — a role set before that had nowhere to go.
   */
  async syncRoles(tripId: number): Promise<void> {
    const approvers = await this.prisma.tripMember.findMany({
      where: {
        tripId,
        inviteStatus: InviteStatus.ACCEPTED,
        role: { in: [TripMemberRole.HOST, TripMemberRole.CO_HOST] },
      },
      select: { userId: true },
    });
    for (const approver of approvers) {
      await this.setMemberRole(tripId, approver.userId, true);
    }
  }

  /**
   * The members a trip allows to approve an above-threshold spend, or null when
   * it allows anyone.
   *
   * Mirrors the rule the program enforces: the restriction applies only once a
   * trip has at least two approvers, so a trip whose sole approver raised the
   * payment is not left unable to pay it. Null rather than the whole member
   * list, so a caller can tell "anyone" from "these people".
   */
  async approverUserIds(tripId: number): Promise<number[] | null> {
    const approvers = await this.prisma.tripMember.findMany({
      where: {
        tripId,
        inviteStatus: InviteStatus.ACCEPTED,
        role: { in: [TripMemberRole.HOST, TripMemberRole.CO_HOST] },
      },
      select: { userId: true },
    });
    return approvers.length >= MIN_APPROVERS_TO_RESTRICT
      ? approvers.map((approver) => approver.userId)
      : null;
  }

  /**
   * Mirrors the vault having closed on chain.
   *
   * Nothing wrote this before, so a settled vault stayed ACTIVE here forever:
   * the drift check reads every active vault, and would have gone on reading a
   * closed one's empty account and reporting the gap every five minutes.
   */
  async markClosed(tripId: number): Promise<void> {
    await this.prisma.tripVault.update({
      where: { tripId },
      data: { status: VaultStatus.CLOSED },
    });
    this.invalidateBalance(tripId);
  }

  async getBalance(
    tripId: number,
  ): Promise<{
    balanceMicro: bigint;
    vaultPda: string;
    usdcAta: string;
    treasuryAta: string;
    spendRecipientAta: string | null;
  }> {
    const vault = await this.requireVault(tripId);

    const treasuryAta = this.solana.treasuryAta().toBase58();
    let spendRecipientAta: string | null = null;
    try {
      spendRecipientAta = getAssociatedTokenAddressSync(
        this.solana.usdcMint,
        this.solana.receiverPublicKey,
      ).toBase58();
    } catch {
      // Balance reads must work before payout keys are configured.
    }

    const accounts = {
      vaultPda: vault.vaultPda,
      usdcAta: vault.usdcAta,
      treasuryAta,
      spendRecipientAta,
    };

    // After settlement the ATA (and often the PDA) are closed for rent reclaim.
    // Clients still call this to ask "does this trip have a vault?" — a missing
    // account must not look like "no vault", or ended trips fall back to the
    // pre-web3 settlement UI.
    if (vault.status === VaultStatus.CLOSED) {
      return { balanceMicro: 0n, ...accounts };
    }

    const cached = this.balanceCache.get(tripId);
    if (cached && cached.expiresAt > Date.now()) {
      return { balanceMicro: cached.balanceMicro, ...accounts };
    }

    let balanceMicro = 0n;
    try {
      balanceMicro = await this.solana.getTokenBalance(
        new PublicKey(vault.usdcAta),
      );
    } catch {
      // ATA not created yet, or already closed while DB still says ACTIVE.
      balanceMicro = 0n;
    }
    this.balanceCache.set(tripId, {
      balanceMicro,
      expiresAt: Date.now() + BALANCE_CACHE_MS,
    });
    return { balanceMicro, ...accounts };
  }

  /**
   * Drops the cached balance for a trip.
   *
   * Called by whatever moved the money. Someone who has just deposited should
   * see their own deposit, and a few seconds of "did that work?" is worse than
   * the RPC call the cache saves.
   */
  invalidateBalance(tripId: number): void {
    this.balanceCache.delete(tripId);
  }

  /**
   * Builds the deposit transaction for the member to sign. The server signs as
   * fee payer; the member signs as the token authority.
   */
  async buildDepositTx(
    tripId: number,
    userId: number,
    amountMicro: bigint,
  ): Promise<string> {
    this.assertConfigured();

    if (amountMicro <= 0n) {
      throw new BadRequestException('amountMicro must be positive');
    }

    const vault = await this.requireVault(tripId);
    const wallet = await this.prisma.walletAccount.findUnique({
      where: { userId },
    });
    if (!wallet) {
      throw new BadRequestException('Link a wallet before depositing');
    }

    // Existing vaults may predate ensureTreasuryAta-on-create; do it here too.
    await this.solana.ensureTreasuryAta();

    const owner = new PublicKey(wallet.publicKey);
    const ownerAta = getAssociatedTokenAddressSync(this.solana.usdcMint, owner);

    const ix = await this.solana.program.methods
      .deposit(new BN(amountMicro.toString()))
      .accountsPartial({
        vault: new PublicKey(vault.vaultPda),
        treasuryAta: this.solana.treasuryAta(),
        ownerAta,
        owner,
        usdcMint: this.solana.usdcMint,
      })
      .instruction();

    return this.solana.buildUnsignedTx([ix]);
  }

  /**
   * Submits a deposit the member signed on device and returns its signature.
   *
   * Deposits go through the server rather than straight to an RPC node because
   * the server is the fee payer and has already partial-signed the transaction.
   * Without this the signed bytes would have nowhere to go and the deposit would
   * silently never land.
   *
   * Idempotent at the chain level: resubmitting the same signed transaction
   * yields the same signature rather than a second transfer.
   */
  async submitDeposit(
    tripId: number,
    userId: number,
    signedTx: string,
    amountMicro: bigint,
  ): Promise<string> {
    this.assertConfigured();
    const vault = await this.requireVault(tripId);

    const signature = await this.solana.broadcastSigned(signedTx);

    // Credit the net after the 0.1% skim — that is what landed in the vault.
    const feeMicro = (amountMicro * 10n) / 10_000n;
    const netMicro = amountMicro - feeMicro;

    const row = await this.prisma.vaultTransaction.create({
      data: {
        tripVaultId: vault.id,
        userId,
        kind: VaultTxKind.DEPOSIT,
        status: VaultTxStatus.PENDING,
        amountMicro: netMicro,
        signature,
      },
    });

    await this.solana.confirmSigned(signedTx, signature);
    await this.prisma.vaultTransaction.update({
      where: { id: row.id },
      data: { status: VaultTxStatus.CONFIRMED },
    });

    this.invalidateBalance(tripId);
    // Nothing announced a deposit before, so every other member's screen sat on
    // a stale balance and an incomplete history until they left and came back.
    const actor = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { displayName: true },
    });
    this.trips.sendVaultBalanceChanged(tripId, {
      kind: VaultTxKind.DEPOSIT,
      actorUserId: userId,
      actorName: actor?.displayName ?? '',
      amountMicro: amountMicro.toString(),
    });
    this.logger.log(`deposit ${signature} confirmed for trip ${tripId}`);
    return signature;
  }

  /**
   * Throws when a trip still holds funds on chain. Called before trip deletion so
   * USDC cannot be stranded in a vault the app can no longer reach.
   */
  async assertDeletable(tripId: number): Promise<void> {
    const vault = await this.prisma.tripVault.findUnique({ where: { tripId } });
    if (!vault) {
      return;
    }
    const balance = await this.solana.getTokenBalance(
      new PublicKey(vault.usdcAta),
    );
    if (balance > 0n) {
      throw new BadRequestException(
        'Settle or withdraw the trip vault before deleting the trip',
      );
    }
  }
}
