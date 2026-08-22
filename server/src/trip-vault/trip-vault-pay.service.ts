import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import {
  ExpenseCategory,
  InviteStatus,
  TripMemberRole,
  TripStatus,
  VaultStatus,
  VaultTransaction,
  VaultTxKind,
  VaultTxStatus,
} from '@prisma/client';
import { getAssociatedTokenAddressSync } from '@solana/spl-token';
import { PublicKey } from '@solana/web3.js';
import BN from 'bn.js';

import { PrismaService } from '../prisma/prisma.service';
import { SolanaService } from '../solana/solana.service';
import { PAYOUT_PROVIDER } from '../payout/payout-provider.interface';
// Imported as a type: an interface in a decorated constructor breaks
// emitDecoratorMetadata under isolatedModules unless it is a type-only import.
import type { PayoutProvider } from '../payout/payout-provider.interface';
import { decodeVietQr } from '../payout/vietqr';
import { ExpensesService } from '../expenses/expenses.service';
import { TripsHandler } from '../realtime/handlers/trips.handler';
import { TripVaultService } from './trip-vault.service';

export interface PayQuote {
  recipientName: string;
  bankBin: string;
  accountNumber: string;
  amountVnd: bigint;
  amountUsdcMicro: bigint;
  feeMicro: bigint;
  rate: string;
  needsApproval: boolean;
  description: string | null;
}

export interface PreparePaymentInput {
  qrPayload: string;
  amountVnd?: bigint;
  name: string;
  category: ExpenseCategory;
  shareWithUserIds: number[];
}

@Injectable()
export class TripVaultPayService {
  private readonly logger = new Logger(TripVaultPayService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly vaultService: TripVaultService,
    private readonly solana: SolanaService,
    @Inject(PAYOUT_PROVIDER) private readonly payout: PayoutProvider,
    private readonly expenses: ExpensesService,
    private readonly trips: TripsHandler,
  ) {}

  /** Deterministic so the reconciliation cron can retry without duplicating. */
  payoutRefFor(vaultTransactionId: number): string {
    return `vault-tx-${vaultTransactionId}`;
  }

  /**
   * Who a QR code pays, without pricing anything.
   *
   * The amount screen shows the recipient's real name while the user is still
   * typing an amount, and most Vietnamese shop codes carry no amount at all, so
   * quote cannot answer this: it refuses without one. The name comes from the
   * bank rather than from the code, which is the point — it is what tells
   * someone they are paying who they think they are.
   */
  async lookupRecipient(qrPayload: string): Promise<{
    recipientName: string;
    bankBin: string;
    accountNumber: string;
    amountVnd: bigint | null;
    description: string | null;
  }> {
    const decoded = decodeVietQr(qrPayload);
    const recipient = await this.payout.validateRecipient({
      bankBin: decoded.bankBin,
      accountNumber: decoded.accountNumber,
    });
    if (!recipient) {
      throw new BadRequestException('Recipient account could not be validated');
    }
    return {
      recipientName: recipient.accountName,
      bankBin: decoded.bankBin,
      accountNumber: decoded.accountNumber,
      amountVnd: decoded.amountVnd,
      description: decoded.description,
    };
  }

  async quote(
    tripId: number,
    userId: number,
    qrPayload: string,
    amountVndOverride?: bigint,
  ): Promise<PayQuote> {
    const vault = await this.vaultService.requireVault(tripId);
    const decoded = decodeVietQr(qrPayload);

    const amountVnd = decoded.amountVnd ?? amountVndOverride;
    if (!amountVnd || amountVnd <= 0n) {
      throw new BadRequestException(
        'This QR code carries no amount; supply amountVnd',
      );
    }

    const recipient = await this.payout.validateRecipient({
      bankBin: decoded.bankBin,
      accountNumber: decoded.accountNumber,
    });
    if (!recipient) {
      throw new BadRequestException('Recipient account could not be validated');
    }

    const priced = await this.payout.quote({ amountVnd });

    const { balanceMicro } = await this.vaultService.getBalance(tripId);
    if (priced.amountUsdcMicro + priced.feeMicro > balanceMicro) {
      throw new BadRequestException(
        'Vault balance is not enough for this payment',
      );
    }

    return {
      recipientName: recipient.accountName,
      bankBin: decoded.bankBin,
      accountNumber: decoded.accountNumber,
      amountVnd,
      amountUsdcMicro: priced.amountUsdcMicro,
      feeMicro: priced.feeMicro,
      rate: priced.rate,
      needsApproval: priced.amountUsdcMicro > vault.thresholdMicro,
      description: decoded.description,
    };
  }

  /**
   * Records the intent and returns the transaction for the payer to sign. Above
   * the threshold this builds propose_spend instead of spend; the caller shows
   * "awaiting approval" rather than a failure.
   */
  async preparePayment(
    tripId: number,
    userId: number,
    input: PreparePaymentInput,
  ): Promise<{
    base64Tx: string;
    vaultTransactionId: number;
    needsApproval: boolean;
  }> {
    const priced = await this.quote(
      tripId,
      userId,
      input.qrPayload,
      input.amountVnd,
    );
    const vault = await this.vaultService.requireVault(tripId);

    const record = await this.prisma.vaultTransaction.create({
      data: {
        tripVaultId: vault.id,
        userId,
        kind: VaultTxKind.SPEND,
        status: VaultTxStatus.PENDING,
        amountMicro: priced.amountUsdcMicro,
        amountVnd: priced.amountVnd,
        bankBin: priced.bankBin,
        bankAccount: priced.accountNumber,
        recipientName: priced.recipientName,
        qrPayload: input.qrPayload,
        feeMicro: priced.feeMicro,
        rate: priced.rate,
        note: priced.description,
        expenseName: input.name,
        expenseCategory: input.category,
        shareWithUserIds: input.shareWithUserIds,
      },
    });

    await this.prisma.vaultTransaction.update({
      where: { id: record.id },
      data: { payoutRef: this.payoutRefFor(record.id) },
    });

    const wallet = await this.prisma.walletAccount.findUnique({
      where: { userId },
    });
    if (!wallet) {
      throw new BadRequestException('Link a wallet before paying');
    }
    const signer = new PublicKey(wallet.publicKey);

    const base64Tx = await this.buildSpendTx(
      tripId,
      priced.amountUsdcMicro,
      signer,
    );

    // Nothing about the proposal is recorded or announced here. This method only
    // builds a transaction; whether it reaches the chain is decided later, and
    // the address it will occupy is not knowable until it does. Predicting it
    // from the current nonce also gave two members preparing at the same moment
    // the same address, and only one of them could be right.

    return {
      base64Tx,
      vaultTransactionId: record.id,
      needsApproval: priced.needsApproval,
    };
  }

  /**
   * Submits the signed on-chain leg, then attempts the fiat leg.
   *
   * The three outcomes are deliberately asymmetric:
   * - SUCCESS  confirms the row and creates the expense with its split
   * - FAILED   marks the row failed; the cron reverts the on-chain transfer
   * - UNKNOWN  leaves the row PENDING. Never revert here: the payout may well
   *            have gone through and reverting would pay twice.
   */
  /// Loads a vault transaction and proves it belongs to `tripId`.
  ///
  /// The route is nested under a trip, so without this check the trip segment is
  /// decorative: any authenticated member of any trip could act on any other
  /// trip's transaction just by knowing its id.
  private async requireTransactionInTrip(
    vaultTransactionId: number,
    tripId: number,
  ): Promise<VaultTransaction> {
    const record = await this.prisma.vaultTransaction.findUnique({
      where: { id: vaultTransactionId },
      include: { tripVault: { select: { tripId: true } } },
    });
    if (!record || record.tripVault.tripId !== tripId) {
      throw new NotFoundException('Vault transaction not found');
    }
    return record;
  }

  async submitPayment(
    vaultTransactionId: number,
    signedTx: string,
    tripId: number,
  ): Promise<VaultTransaction> {
    const record = await this.requireTransactionInTrip(
      vaultTransactionId,
      tripId,
    );
    if (record.status !== VaultTxStatus.PENDING) {
      return record;
    }

    // Recorded before the wait, not after. Confirming is a second network call,
    // and losing it used to lose the signature with it — the payment had left
    // the vault and nothing on this side could say so, or even ask. With the
    // signature stored the reconcile job can settle it whatever happens next.
    const signature = await this.solana.broadcastSigned(signedTx);
    await this.prisma.vaultTransaction.update({
      where: { id: record.id },
      data: { signature },
    });
    await this.solana.confirmSigned(signedTx, signature);

    // An above-threshold payment reaches here twice: once for the proposal and
    // again for the approval that executes it. Only the second moves any USDC,
    // so only the second may pay the merchant — paying on the first would hand
    // over dong for money still sitting in the vault.
    const vault = await this.vaultService.requireVault(tripId);
    const needsApproval = record.amountMicro > vault.thresholdMicro;

    if (needsApproval && !record.proposalPda) {
      // The proposal leg. Its address is read back from the chain now that it
      // exists, rather than guessed before it did — which is what left rows
      // pointing at accounts that were never created, offering an approval that
      // could only fail. Asking for that approval waits until here for the same
      // reason: there is now something to approve.
      const proposalPda = await this.landedProposalPda(vault.vaultPda);
      await this.prisma.vaultTransaction.update({
        where: { id: record.id },
        data: { proposalPda },
      });
      this.trips.sendVaultApprovalRequested(tripId, {
        vaultTransactionId: record.id,
        amountVnd: record.amountVnd?.toString() ?? '0',
        recipientName: record.recipientName ?? '',
        proposedByUserId: record.userId,
        approverUserIds: await this.vaultService.approverUserIds(tripId),
      });
      return this.prisma.vaultTransaction.findUniqueOrThrow({
        where: { id: record.id },
      });
    }

    if (needsApproval && !record.approvedAt) {
      if (!(await this.isProposalExecuted(record.proposalPda!))) {
        return this.prisma.vaultTransaction.findUniqueOrThrow({
          where: { id: record.id },
        });
      }
      await this.prisma.vaultTransaction.update({
        where: { id: record.id },
        data: { approvedAt: new Date() },
      });
    }

    const result = await this.payout.payout({
      bankBin: record.bankBin!,
      accountNumber: record.bankAccount!,
      amountVnd: record.amountVnd!,
      reference: record.payoutRef ?? this.payoutRefFor(record.id),
    });

    if (result.outcome === 'SUCCESS') {
      const vault = await this.prisma.tripVault.findUniqueOrThrow({
        where: { id: record.tripVaultId },
        select: { tripId: true },
      });
      const expense = await this.expenses.createFromVault({
        tripId: vault.tripId,
        paidByUserId: record.userId ?? undefined,
        amountVnd: record.amountVnd!,
        amountUsdcMicro: record.amountMicro,
        rate: record.rate,
        name: record.expenseName ?? 'Vault payment',
        category: record.expenseCategory ?? ExpenseCategory.OTHER,
        shareWithUserIds: record.shareWithUserIds,
      });
      this.vaultService.invalidateBalance(vault.tripId);
      const actor = record.userId
        ? await this.prisma.user.findUnique({
            where: { id: record.userId },
            select: { displayName: true },
          })
        : null;
      this.trips.sendVaultBalanceChanged(vault.tripId, {
        kind: VaultTxKind.SPEND,
        actorUserId: record.userId,
        actorName: actor?.displayName ?? '',
        amountMicro: record.amountMicro.toString(),
      });
      return this.prisma.vaultTransaction.update({
        where: { id: record.id },
        data: {
          status: VaultTxStatus.CONFIRMED,
          payoutStatus: result.outcome,
          expenseId: expense.id,
        },
      });
    }

    if (result.outcome === 'FAILED') {
      return this.prisma.vaultTransaction.update({
        where: { id: record.id },
        data: {
          status: VaultTxStatus.FAILED,
          payoutStatus: result.outcome,
          failureCode: result.failureCode,
        },
      });
    }

    this.logger.warn(
      `payout ${record.payoutRef} returned ${result.outcome}; leaving PENDING for the reconcile cron`,
    );
    return this.prisma.vaultTransaction.update({
      where: { id: record.id },
      data: { payoutStatus: result.outcome },
    });
  }

  /**
   * Marker that an above-threshold spend is open on the vault.
   *
   * Format `vaultPda:totalSpentAtPropose`. Cleared slot + higher totalSpent
   * means execute; cleared slot + same totalSpent means cancel.
   */
  private async landedProposalPda(vaultPda: string): Promise<string> {
    const onChain = await this.solana.program.account.tripVault.fetch(
      new PublicKey(vaultPda),
    );
    if (!onChain.hasActiveSpend) {
      throw new Error('propose_spend did not open an active spend');
    }
    return `${vaultPda}:${onChain.totalSpent.toString()}`;
  }

  /**
   * Whether the second signature has landed and the transfer has run.
   */
  private async isProposalExecuted(proposalPda: string): Promise<boolean> {
    const [vaultPda, spentAtPropose] = proposalPda.split(':');
    if (!vaultPda || spentAtPropose === undefined) {
      return false;
    }
    const onChain = await this.solana.program.account.tripVault.fetch(
      new PublicKey(vaultPda),
    );
    if (onChain.hasActiveSpend) {
      return false;
    }
    return BigInt(onChain.totalSpent.toString()) > BigInt(spentAtPropose);
  }

  /**
   * Chooses the instruction by threshold. At or below it a single member
   * signature is enough; above it the transaction only creates a proposal and a
   * second member has to approve before any funds move.
   */
  async buildSpendTx(
    tripId: number,
    amountMicro: bigint,
    signer: PublicKey,
  ): Promise<string> {
    const vault = await this.vaultService.requireVault(tripId);
    const vaultPda = new PublicKey(vault.vaultPda);
    const recipientAta = getAssociatedTokenAddressSync(
      this.solana.usdcMint,
      this.solana.receiverPublicKey,
    );

    if (amountMicro <= vault.thresholdMicro) {
      const ix = await this.solana.program.methods
        .spend(new BN(amountMicro.toString()))
        .accountsPartial({
          vault: vaultPda,
          signer,
          recipientAta,
          usdcMint: this.solana.usdcMint,
        })
        .instruction();
      return this.solana.buildUnsignedTx([ix]);
    }

    const ix = await this.solana.program.methods
      .proposeSpend(new BN(amountMicro.toString()))
      .accountsPartial({
        vault: vaultPda,
        signer,
        recipientAta,
      })
      .instruction();
    return this.solana.buildUnsignedTx([ix]);
  }

  /** Builds the second signature for an above-threshold payment. */
  async buildApprovalTx(
    vaultTransactionId: number,
    userId: number,
    tripId: number,
  ): Promise<string> {
    const record = await this.requireTransactionInTrip(
      vaultTransactionId,
      tripId,
    );
    if (!record.proposalPda) {
      throw new BadRequestException('This payment did not need approval');
    }

    const wallet = await this.prisma.walletAccount.findUnique({
      where: { userId },
    });
    if (!wallet) {
      throw new BadRequestException('Link a wallet before approving');
    }

    const vault = await this.prisma.tripVault.findUniqueOrThrow({
      where: { id: record.tripVaultId },
    });
    const recipientAta = getAssociatedTokenAddressSync(
      this.solana.usdcMint,
      this.solana.receiverPublicKey,
    );

    const ix = await this.solana.program.methods
      .approveSpend()
      .accountsPartial({
        vault: new PublicKey(vault.vaultPda),
        signer: new PublicKey(wallet.publicKey),
        recipientAta,
        usdcMint: this.solana.usdcMint,
      })
      .instruction();

    return this.solana.buildUnsignedTx([ix]);
  }

  /**
   * Cancels the active above-threshold spend. Proposer, host, or co-host.
   */
  async buildCancelTx(
    vaultTransactionId: number,
    userId: number,
    tripId: number,
  ): Promise<string> {
    const record = await this.requireTransactionInTrip(
      vaultTransactionId,
      tripId,
    );
    if (!record.proposalPda) {
      throw new BadRequestException('This payment has no open proposal');
    }

    const wallet = await this.prisma.walletAccount.findUnique({
      where: { userId },
    });
    if (!wallet) {
      throw new BadRequestException('Link a wallet before cancelling');
    }

    const vault = await this.prisma.tripVault.findUniqueOrThrow({
      where: { id: record.tripVaultId },
    });

    const ix = await this.solana.program.methods
      .cancelSpend()
      .accountsPartial({
        vault: new PublicKey(vault.vaultPda),
        signer: new PublicKey(wallet.publicKey),
      })
      .instruction();

    return this.solana.buildUnsignedTx([ix]);
  }

  async submitCancel(
    vaultTransactionId: number,
    signedTx: string,
    tripId: number,
  ): Promise<VaultTransaction> {
    const record = await this.requireTransactionInTrip(
      vaultTransactionId,
      tripId,
    );
    const signature = await this.solana.broadcastSigned(signedTx);
    await this.solana.confirmSigned(signedTx, signature);
    return this.prisma.vaultTransaction.update({
      where: { id: record.id },
      data: {
        status: VaultTxStatus.FAILED,
        failureCode: 'cancelled',
        signature,
        proposalPda: null,
      },
    });
  }

  /**
   * Edits share / name / category on a confirmed spend. Amount stays locked —
   * the on-chain transfer already happened.
   */
  async updateSpendMetadata(
    tripId: number,
    vaultTransactionId: number,
    callerUserId: number,
    input: {
      name?: string;
      category?: ExpenseCategory;
      shareWithUserIds?: number[];
    },
  ): Promise<VaultTransaction> {
    if (
      input.name === undefined &&
      input.category === undefined &&
      input.shareWithUserIds === undefined
    ) {
      throw new BadRequestException('Nothing to update');
    }

    const record = await this.requireTransactionInTrip(
      vaultTransactionId,
      tripId,
    );
    if (record.kind !== VaultTxKind.SPEND) {
      throw new BadRequestException('Only spend transactions can be edited');
    }
    if (record.status !== VaultTxStatus.CONFIRMED) {
      throw new BadRequestException('Only confirmed spends can be edited');
    }

    const vault = await this.vaultService.requireVault(tripId);
    if (vault.status === VaultStatus.CLOSED) {
      throw new BadRequestException(
        'Cannot edit spends after the vault has settled',
      );
    }

    const trip = await this.prisma.trip.findUniqueOrThrow({
      where: { id: tripId },
      select: { status: true },
    });
    if (trip.status === TripStatus.ENDED) {
      throw new BadRequestException('Cannot edit spends after the trip has ended');
    }

    const isHost = await this.prisma.tripMember.findFirst({
      where: {
        tripId,
        userId: callerUserId,
        inviteStatus: InviteStatus.ACCEPTED,
        role: { in: [TripMemberRole.HOST, TripMemberRole.CO_HOST] },
      },
      select: { id: true },
    });
    if (record.userId !== callerUserId && !isHost) {
      throw new ForbiddenException(
        'Only the payer or a host can edit this transaction',
      );
    }

    let nextShares = record.shareWithUserIds;
    if (input.shareWithUserIds !== undefined) {
      if (input.shareWithUserIds.length > 0) {
        const accepted = await this.prisma.tripMember.findMany({
          where: {
            tripId,
            inviteStatus: InviteStatus.ACCEPTED,
            userId: { in: input.shareWithUserIds },
          },
          select: { userId: true },
        });
        const acceptedIds = new Set(accepted.map((row) => row.userId));
        const invalid = input.shareWithUserIds.filter(
          (id) => !acceptedIds.has(id),
        );
        if (invalid.length > 0) {
          throw new BadRequestException(
            'shareWithUserIds must be accepted trip members',
          );
        }
      }
      nextShares = input.shareWithUserIds;
    }

    const updated = await this.prisma.vaultTransaction.update({
      where: { id: record.id },
      data: {
        ...(input.name !== undefined ? { expenseName: input.name } : {}),
        ...(input.category !== undefined
          ? { expenseCategory: input.category }
          : {}),
        ...(input.shareWithUserIds !== undefined
          ? { shareWithUserIds: nextShares }
          : {}),
      },
    });

    if (record.expenseId) {
      await this.expenses.updateExpense(tripId, record.expenseId, callerUserId, {
        ...(input.name !== undefined ? { name: input.name } : {}),
        ...(input.category !== undefined ? { category: input.category } : {}),
        ...(input.shareWithUserIds !== undefined
          ? {
              memberIds:
                nextShares.length > 0
                  ? nextShares
                  : (
                      await this.prisma.tripMember.findMany({
                        where: { tripId, inviteStatus: InviteStatus.ACCEPTED },
                        select: { userId: true },
                      })
                    ).map((row) => row.userId),
            }
          : {}),
      });
    }

    return updated;
  }
}
