import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  ActivityAction,
  Currency,
  ExpenseCategory,
  InviteStatus,
  Prisma,
} from '@prisma/client';
import { resolveAmounts } from '../common/currency/resolve-amounts';
import { ExchangeRatesService } from '../exchange-rates/exchange-rates.service';
import { PrismaService } from '../prisma/prisma.service';
import { TripsHandler } from '../realtime/handlers/trips.handler';
import { StorageService } from '../storage/storage.service';
import { TripActivityService } from '../trip-activity/trip-activity.service';
import { AnalyticsService } from '../analytics/analytics.service';
import { ANALYTICS_EVENTS } from '../analytics/constants/events';
import { CreateExpenseDto } from './dto/create-expense.dto';
import { CreateReceiptExpenseDto } from './dto/create-receipt-expense.dto';
import { UpdateExpenseDto } from './dto/update-expense.dto';
import { ExpenseDto } from './dto/expense.dto';
import { ExpenseShareDto } from './dto/expense-share.dto';
import {
  SharedMemberPreviewDto,
  ExpenseSummaryDto,
} from './dto/expense-summary.dto';
import {
  TripBreakdownDto,
  MemberBreakdownDto,
  BreakdownExpenseItemDto,
} from './dto/expense-breakdown.dto';
import { ListExpensesQueryDto } from './dto/list-expenses-query.dto';
import { SettleShareDto } from './dto/settle-share.dto';

const EXPENSE_DETAIL_INCLUDE = {
  paidBy: {
    select: { id: true, displayName: true, avatarUrl: true },
  },
  shares: {
    include: {
      user: {
        select: { id: true, displayName: true, avatarUrl: true },
      },
    },
  },
} as const;

@Injectable()
export class ExpensesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityService: TripActivityService,
    private readonly storageService: StorageService,
    private readonly exchangeRatesService: ExchangeRatesService,
    private readonly tripsHandler: TripsHandler,
    private readonly analytics: AnalyticsService,
  ) {}

  async createExpense(
    tripId: number,
    userId: number,
    dto: CreateExpenseDto,
  ): Promise<ExpenseDto> {
    await this.assertMember(tripId, userId);

    const members = await this.prisma.tripMember.findMany({
      where: {
        tripId,
        inviteStatus: InviteStatus.ACCEPTED,
        userId: { in: dto.memberIds },
      },
    });
    const acceptedMemberIds = members.map((m) => m.userId);
    if (acceptedMemberIds.length === 0) {
      throw new BadRequestException(
        'No accepted trip members found in the provided list',
      );
    }

    const trip = await this.prisma.trip.findUniqueOrThrow({
      where: { id: tripId },
      select: { currency: true },
    });

    const resolved = await resolveAmounts(
      this.exchangeRatesService,
      trip.currency,
      dto,
    );

    const category = dto.category ?? ExpenseCategory.OTHER;
    const homeAmountNumber = Number(resolved.amount);
    const shares = this.splitAmount(homeAmountNumber, acceptedMemberIds.length);

    const expense = await this.prisma.$transaction(async (tx) => {
      const created = await tx.expense.create({
        data: {
          tripId,
          paidById: userId,
          name: dto.name,
          amount: resolved.amount,
          category,
          note: dto.note,
          expenseDate: new Date(dto.expenseDate),
          originalAmount: resolved.originalAmount,
          originalCurrency: resolved.originalCurrency,
          exchangeRate: resolved.exchangeRate,
        },
      });

      await tx.expenseShare.createMany({
        data: acceptedMemberIds.map((memberId, index) => ({
          expenseId: created.id,
          userId: memberId,
          shareAmount: shares[index],
        })),
      });

      return created;
    });

    this.activityService.log(
      tripId,
      userId,
      ActivityAction.EXPENSE_CREATED,
      expense.id,
      {
        name: dto.name,
        amount: homeAmountNumber,
      },
    );

    void this.analytics.track(ANALYTICS_EVENTS.EXPENSE_ADDED, {
      userId,
      properties: {
        tripId,
        expenseId: expense.id,
        amount: homeAmountNumber,
        category: expense.category,
        source: 'manual',
      },
    });

    const detail = await this.findExpenseDetail(expense.id);
    if (resolved.isStale) {
      detail.rateStale = true;
    }
    return detail;
  }

  async createReceiptExpense(
    tripId: number,
    userId: number,
    dto: CreateReceiptExpenseDto,
  ): Promise<ExpenseDto> {
    await this.assertMember(tripId, userId);

    const uniqueUserIds = [...new Set(dto.items.map((item) => item.userId))];

    const members = await this.prisma.tripMember.findMany({
      where: {
        tripId,
        inviteStatus: InviteStatus.ACCEPTED,
        userId: { in: uniqueUserIds },
      },
    });
    const acceptedMemberIds = new Set(members.map((m) => m.userId));

    const invalidIds = uniqueUserIds.filter((id) => !acceptedMemberIds.has(id));
    if (invalidIds.length > 0) {
      throw new BadRequestException(
        `No accepted trip members found for user IDs: ${invalidIds.join(', ')}`,
      );
    }

    const trip = await this.prisma.trip.findUniqueOrThrow({
      where: { id: tripId },
      select: { currency: true },
    });

    const round2 = (n: number) => Math.round(n * 100) / 100;

    // Per-user subtotals + grand total, in the ORIGINAL (scanned) currency.
    const origShareMap = new Map<number, number>();
    let origTotal = 0;
    for (const item of dto.items) {
      const current = origShareMap.get(item.userId) ?? 0;
      origShareMap.set(item.userId, round2(current + item.amount));
      origTotal = round2(origTotal + item.amount);
    }

    // Convert to the trip (group) currency exactly the way manual expenses
    // do. Only a currency that differs from the trip currency triggers an
    // FX lookup; same-currency / unset degrades to rate = 1 with no getRate
    // call (mirrors createExpense's amount-only path).
    const isForeign =
      dto.originalCurrency != null && dto.originalCurrency !== trip.currency;
    const resolved = await resolveAmounts(
      this.exchangeRatesService,
      trip.currency,
      {
        amount: origTotal,
        originalAmount: isForeign ? origTotal : undefined,
        originalCurrency: isForeign ? dto.originalCurrency : undefined,
      },
    );

    const rate = Number(resolved.exchangeRate);
    const convertedTotal = round2(Number(resolved.amount));

    // Convert each per-user subtotal with the SAME rate, then reconcile the
    // rounding residual onto the largest share so shares sum EXACTLY to the
    // converted total (mirrors splitAmount's "residual on one share").
    const shareEntries = Array.from(origShareMap.entries()).map(
      ([memberId, origShare]) => ({
        memberId,
        shareAmount: round2(origShare * rate),
      }),
    );
    if (shareEntries.length > 0) {
      const sumShares = round2(
        shareEntries.reduce((acc, e) => acc + e.shareAmount, 0),
      );
      const residual = round2(convertedTotal - sumShares);
      if (residual !== 0) {
        let largestIdx = 0;
        for (let i = 1; i < shareEntries.length; i++) {
          if (
            shareEntries[i].shareAmount > shareEntries[largestIdx].shareAmount
          ) {
            largestIdx = i;
          }
        }
        shareEntries[largestIdx].shareAmount = round2(
          shareEntries[largestIdx].shareAmount + residual,
        );
      }
    }

    const category = dto.category ?? ExpenseCategory.FOOD;

    const expense = await this.prisma.$transaction(async (tx) => {
      const created = await tx.expense.create({
        data: {
          tripId,
          paidById: userId,
          name: dto.name,
          amount: resolved.amount,
          category,
          note: dto.note,
          expenseDate: new Date(dto.expenseDate),
          originalAmount: resolved.originalAmount,
          originalCurrency: resolved.originalCurrency,
          exchangeRate: resolved.exchangeRate,
        },
      });

      await tx.expenseShare.createMany({
        data: shareEntries.map(({ memberId, shareAmount }) => ({
          expenseId: created.id,
          userId: memberId,
          shareAmount,
        })),
      });

      return created;
    });

    this.activityService.log(
      tripId,
      userId,
      ActivityAction.EXPENSE_CREATED,
      expense.id,
      {
        name: dto.name,
        amount: convertedTotal,
      },
    );

    void this.analytics.track(ANALYTICS_EVENTS.EXPENSE_ADDED, {
      userId,
      properties: {
        tripId,
        expenseId: expense.id,
        amount: convertedTotal,
        category,
        source: 'receipt',
      },
    });

    const detail = await this.findExpenseDetail(expense.id);
    if (resolved.isStale) {
      detail.rateStale = true;
    }
    return detail;
  }

  async listExpenses(
    tripId: number,
    userId: number,
    query: ListExpensesQueryDto,
  ): Promise<ExpenseSummaryDto[]> {
    await this.assertMember(tripId, userId);

    const expenses = await this.prisma.expense.findMany({
      where: {
        tripId,
        ...(query.category ? { category: query.category } : {}),
      },
      include: {
        paidBy: {
          select: { id: true, displayName: true, avatarUrl: true },
        },
        shares: {
          include: {
            user: {
              select: { id: true, avatarUrl: true },
            },
          },
        },
      },
      orderBy: { expenseDate: 'desc' },
    });

    return Promise.all(
      expenses.map((expense) => this.formatExpenseSummary(expense)),
    );
  }

  async getExpense(
    tripId: number,
    expenseId: number,
    userId: number,
  ): Promise<ExpenseDto> {
    await this.assertMember(tripId, userId);
    await this.assertExpenseBelongsToTrip(expenseId, tripId);
    return this.findExpenseDetail(expenseId);
  }

  async updateExpense(
    tripId: number,
    expenseId: number,
    userId: number,
    dto: UpdateExpenseDto,
  ): Promise<ExpenseDto> {
    await this.assertMember(tripId, userId);
    await this.assertExpenseBelongsToTrip(expenseId, tripId);

    // See budgets.service.ts for the same logic and rationale. Either
    // original-currency fields OR an amount-only edit re-resolves all 4
    // currency fields to keep the invariant amount ≈ originalAmount × rate.
    const originalChanged =
      dto.originalAmount !== undefined || dto.originalCurrency !== undefined;
    const amountChanged = dto.amount !== undefined;
    const needsResolve = originalChanged || amountChanged;

    let resolved: Awaited<ReturnType<typeof resolveAmounts>> | null = null;
    let freshConversionRan = false;

    if (needsResolve) {
      const trip = await this.prisma.trip.findUniqueOrThrow({
        where: { id: tripId },
        select: { currency: true },
      });
      resolved = await resolveAmounts(
        this.exchangeRatesService,
        trip.currency,
        {
          amount: dto.amount,
          originalAmount: dto.originalAmount,
          originalCurrency: dto.originalCurrency,
        },
      );
      freshConversionRan = originalChanged;
    }

    await this.prisma.$transaction(async (tx) => {
      const existingExpense = await tx.expense.findUniqueOrThrow({
        where: { id: expenseId },
        select: { amount: true },
      });

      // Determine the amount to use for share recomputation.
      const nextAmountNumber: number = resolved
        ? Number(resolved.amount)
        : Number(existingExpense.amount);

      const updateData: Prisma.ExpenseUpdateInput = {};
      if (dto.name !== undefined) updateData.name = dto.name;
      if (dto.category !== undefined) updateData.category = dto.category;
      if (dto.note !== undefined) updateData.note = dto.note;
      if (dto.expenseDate !== undefined) {
        updateData.expenseDate = new Date(dto.expenseDate);
      }

      if (resolved) {
        updateData.amount = resolved.amount;
        updateData.originalAmount = resolved.originalAmount;
        updateData.originalCurrency = resolved.originalCurrency;
        updateData.exchangeRate = resolved.exchangeRate;
      }

      if (Object.keys(updateData).length > 0) {
        await tx.expense.update({
          where: { id: expenseId },
          data: updateData,
        });
      }

      if (dto.memberIds !== undefined) {
        const members = await tx.tripMember.findMany({
          where: {
            tripId,
            inviteStatus: InviteStatus.ACCEPTED,
            userId: { in: dto.memberIds },
          },
          select: { userId: true },
        });
        const acceptedMemberIds = Array.from(
          new Set(members.map((member) => member.userId)),
        );
        if (acceptedMemberIds.length === 0) {
          throw new BadRequestException(
            'No accepted trip members found in the provided list',
          );
        }

        const existingShares = await tx.expenseShare.findMany({
          where: { expenseId },
          select: { id: true, userId: true },
        });
        const existingShareUserIds = new Set(
          existingShares.map((share) => share.userId),
        );
        const shareUserIdsToRemove = existingShares
          .map((share) => share.userId)
          .filter((shareUserId) => !acceptedMemberIds.includes(shareUserId));
        const shareUserIdsToAdd = acceptedMemberIds.filter(
          (memberId) => !existingShareUserIds.has(memberId),
        );

        if (shareUserIdsToRemove.length > 0) {
          await tx.expenseShare.deleteMany({
            where: { expenseId, userId: { in: shareUserIdsToRemove } },
          });
        }

        if (shareUserIdsToAdd.length > 0) {
          await tx.expenseShare.createMany({
            data: shareUserIdsToAdd.map((memberId) => ({
              expenseId,
              userId: memberId,
              shareAmount: 0,
            })),
          });
        }
      }

      if (resolved || dto.memberIds !== undefined) {
        const currentShares = await tx.expenseShare.findMany({
          where: { expenseId },
          select: { id: true },
          orderBy: { id: 'asc' },
        });
        const shares = this.splitAmount(nextAmountNumber, currentShares.length);

        for (let i = 0; i < currentShares.length; i++) {
          await tx.expenseShare.update({
            where: { id: currentShares[i].id },
            data: { shareAmount: shares[i] },
          });
        }
      }
    });

    const detail = await this.findExpenseDetail(expenseId);
    // Only flag rateStale when a live rate was actually fetched. Amount-only
    // updates use rate=1 and must not produce a stale flag.
    if (freshConversionRan && resolved?.isStale) {
      detail.rateStale = true;
    }

    this.activityService.log(
      tripId,
      userId,
      ActivityAction.EXPENSE_UPDATED,
      expenseId,
      {
        name: detail.name,
      },
    );

    return detail;
  }

  async deleteExpense(
    tripId: number,
    expenseId: number,
    userId: number,
  ): Promise<void> {
    await this.assertMember(tripId, userId);
    const expense = await this.assertExpenseBelongsToTrip(expenseId, tripId);

    await this.prisma.expense.delete({ where: { id: expenseId } });

    this.activityService.log(
      tripId,
      userId,
      ActivityAction.EXPENSE_DELETED,
      expenseId,
      {
        name: expense.name,
      },
    );
  }

  async settleExpenseShare(
    tripId: number,
    expenseId: number,
    shareId: number,
    userId: number,
    dto: SettleShareDto,
  ): Promise<ExpenseShareDto> {
    await this.assertMember(tripId, userId);

    const share = await this.prisma.expenseShare.findUnique({
      where: { id: shareId },
      include: {
        expense: { select: { tripId: true } },
        user: { select: { id: true, displayName: true, avatarUrl: true } },
      },
    });

    if (!share) {
      throw new NotFoundException('Expense share not found');
    }

    if (share.expenseId !== expenseId || share.expense.tripId !== tripId) {
      throw new NotFoundException('Expense share not found');
    }

    if (share.userId !== userId) {
      throw new ForbiddenException(
        'Only the share owner can settle their share',
      );
    }

    const updated = await this.prisma.expenseShare.update({
      where: { id: shareId },
      data: {
        isSettled: dto.isSettled,
        settledAt: dto.isSettled ? new Date() : null,
      },
      include: {
        user: { select: { id: true, displayName: true, avatarUrl: true } },
      },
    });

    this.activityService.log(
      tripId,
      userId,
      ActivityAction.EXPENSE_SETTLED,
      shareId,
      {
        displayName: updated.user.displayName,
        isSettled: dto.isSettled,
      },
    );

    return this.formatShare(updated);
  }

  async getTripBreakdown(
    tripId: number,
    userId: number,
  ): Promise<TripBreakdownDto> {
    await this.assertMember(tripId, userId);

    const [expenses, members, budgets] = await Promise.all([
      this.prisma.expense.findMany({
        where: { tripId },
        include: EXPENSE_DETAIL_INCLUDE,
      }),
      this.prisma.tripMember.findMany({
        where: { tripId, inviteStatus: InviteStatus.ACCEPTED },
        include: {
          user: {
            select: { id: true, displayName: true, avatarUrl: true },
          },
        },
      }),
      this.prisma.budget.findMany({
        where: { tripId },
        include: { payments: true },
      }),
    ]);

    const totalSpent = expenses.reduce((sum, e) => sum + Number(e.amount), 0);

    const memberBreakdowns: MemberBreakdownDto[] = members.map((member) => {
      const memberUserId = member.user.id;

      const totalDeposit = budgets.reduce((sum, budget) => {
        const payment = budget.payments.find(
          (p) => p.userId === memberUserId && p.isPaid,
        );
        return sum + (payment ? Number(payment.amount) : 0);
      }, 0);

      const totalPaid = expenses
        .filter((e) => e.paidBy?.id === memberUserId)
        .reduce((sum, e) => sum + Number(e.amount), 0);

      const memberExpenses: BreakdownExpenseItemDto[] = [];
      let totalShare = 0;
      let allSettled = true;

      for (const expense of expenses) {
        for (const share of expense.shares) {
          if (share.user.id === memberUserId) {
            const shareAmount = Number(share.shareAmount);
            totalShare += shareAmount;
            if (!share.isSettled) allSettled = false;
            memberExpenses.push({
              expenseId: expense.id,
              expenseName: expense.name,
              shareAmount,
              isSettled: share.isSettled,
              shareId: share.id,
            });
          }
        }
      }

      return {
        userId: memberUserId,
        displayName: member.user.displayName,
        avatarUrl: member.user.avatarUrl,
        totalDeposit: Math.round(totalDeposit * 100) / 100,
        totalPaid: Math.round(totalPaid * 100) / 100,
        totalShare: Math.round(totalShare * 100) / 100,
        netBalance: Math.round((totalDeposit - totalShare) * 100) / 100,
        isAllSettled: memberExpenses.length === 0 || allSettled,
        expenses: memberExpenses,
      };
    });

    const unsettledCount = memberBreakdowns.filter(
      (m) => !m.isAllSettled,
    ).length;

    return {
      totalSpent: Math.round(totalSpent * 100) / 100,
      unsettledCount,
      members: memberBreakdowns,
    };
  }

  async settleAllShares(
    tripId: number,
    userId: number,
  ): Promise<TripBreakdownDto> {
    await this.assertMember(tripId, userId);

    await this.prisma.expenseShare.updateMany({
      where: {
        userId,
        isSettled: false,
        expense: { tripId },
      },
      data: {
        isSettled: true,
        settledAt: new Date(),
      },
    });

    this.activityService.log(
      tripId,
      userId,
      ActivityAction.EXPENSE_SETTLED,
      undefined,
      { bulk: true },
    );
    this.tripsHandler.sendTripSettlementUpdated(tripId);

    return this.getTripBreakdown(tripId, userId);
  }

  // ── Private helpers ──────────────────────────────────────────────

  private async assertMember(tripId: number, userId: number): Promise<void> {
    const member = await this.prisma.tripMember.findUnique({
      where: { tripId_userId: { tripId, userId } },
    });

    if (!member || member.inviteStatus !== InviteStatus.ACCEPTED) {
      throw new ForbiddenException('You are not a member of this trip');
    }
  }

  private async assertExpenseBelongsToTrip(
    expenseId: number,
    tripId: number,
  ): Promise<{ id: number; name: string }> {
    const expense = await this.prisma.expense.findUnique({
      where: { id: expenseId },
      select: { id: true, name: true, tripId: true },
    });

    if (!expense || expense.tripId !== tripId) {
      throw new NotFoundException('Expense not found');
    }

    return { id: expense.id, name: expense.name };
  }

  private async findExpenseDetail(expenseId: number): Promise<ExpenseDto> {
    const expense = await this.prisma.expense.findUniqueOrThrow({
      where: { id: expenseId },
      include: EXPENSE_DETAIL_INCLUDE,
    });

    return this.formatExpense(expense);
  }

  private async formatExpense(expense: {
    id: number;
    tripId: number;
    name: string;
    amount: any;
    category: ExpenseCategory;
    note: string | null;
    receiptUrl: string | null;
    originalAmount?: any;
    originalCurrency?: Currency | null;
    exchangeRate?: any;
    expenseDate: Date;
    createdAt: Date;
    paidBy: {
      id: number;
      displayName: string;
      avatarUrl: string | null;
    } | null;
    shares: Array<{
      id: number;
      userId: number;
      shareAmount: any;
      isSettled: boolean;
      settledAt: Date | null;
      user: { id: number; displayName: string; avatarUrl: string | null };
    }>;
  }): Promise<ExpenseDto> {
    return {
      id: expense.id,
      tripId: expense.tripId,
      name: expense.name,
      amount: Number(expense.amount),
      category: expense.category,
      note: expense.note,
      receiptUrl: expense.receiptUrl,
      expenseDate: expense.expenseDate.toISOString(),
      createdAt: expense.createdAt.toISOString(),
      paidBy: expense.paidBy
        ? {
            userId: expense.paidBy.id,
            displayName: expense.paidBy.displayName,
            avatarUrl: await this.resolveAvatarUrl(expense.paidBy.avatarUrl),
          }
        : { userId: null, displayName: 'Deleted User', avatarUrl: null },
      shares: await Promise.all(
        expense.shares.map((share) => this.formatShare(share)),
      ),
      originalAmount:
        expense.originalAmount !== null && expense.originalAmount !== undefined
          ? Number(expense.originalAmount)
          : undefined,
      originalCurrency: expense.originalCurrency ?? undefined,
      exchangeRate:
        expense.exchangeRate !== null && expense.exchangeRate !== undefined
          ? Number(expense.exchangeRate)
          : undefined,
    };
  }

  private async formatExpenseSummary(expense: {
    id: number;
    name: string;
    amount: any;
    category: ExpenseCategory;
    expenseDate: Date;
    createdAt: Date;
    paidBy: {
      id: number;
      displayName: string;
      avatarUrl: string | null;
    } | null;
    shares: Array<{
      user: { id: number; avatarUrl: string | null };
    }>;
  }): Promise<ExpenseSummaryDto> {
    const sharedMembers: SharedMemberPreviewDto[] = await Promise.all(
      expense.shares.map(async (share) => ({
        userId: share.user.id,
        avatarUrl: await this.resolveAvatarUrl(share.user.avatarUrl),
      })),
    );

    return {
      id: expense.id,
      name: expense.name,
      amount: Number(expense.amount),
      category: expense.category,
      expenseDate: expense.expenseDate.toISOString(),
      createdAt: expense.createdAt.toISOString(),
      paidBy: expense.paidBy
        ? {
            userId: expense.paidBy.id,
            displayName: expense.paidBy.displayName,
            avatarUrl: await this.resolveAvatarUrl(expense.paidBy.avatarUrl),
          }
        : { userId: null, displayName: 'Deleted User', avatarUrl: null },
      sharedMembers,
    };
  }

  private async formatShare(share: {
    id: number;
    userId: number;
    shareAmount: any;
    isSettled: boolean;
    settledAt: Date | null;
    user: { id: number; displayName: string; avatarUrl: string | null };
  }): Promise<ExpenseShareDto> {
    return {
      id: share.id,
      userId: share.user.id,
      displayName: share.user.displayName,
      avatarUrl: await this.resolveAvatarUrl(share.user.avatarUrl),
      shareAmount: Number(share.shareAmount),
      isSettled: share.isSettled,
      settledAt: share.settledAt?.toISOString() ?? null,
    };
  }

  private async resolveAvatarUrl(value: string | null): Promise<string | null> {
    if (!value) return null;
    if (/^https?:\/\//i.test(value)) return value;
    try {
      const { url } = await this.storageService.getSignedThumbUrl(value);
      return url;
    } catch {
      return null;
    }
  }

  /**
   * Creates an expense on behalf of the vault, splitting it across the members
   * chosen at prepare time. Lives here rather than in the vault module so share
   * splitting has exactly one implementation.
   *
   * Called only after the payout confirms, which may be the reconciliation cron
   * minutes later, so every input comes from the stored VaultTransaction row.
   */
  async createFromVault(input: {
    tripId: number;
    paidByUserId?: number;
    amountVnd: bigint;
    /** What actually left the vault. This is the value the ledger records. */
    amountUsdcMicro: bigint;
    /** VND per USDC at the time the payment was priced. */
    rate: string | null;
    name: string;
    category: ExpenseCategory;
    shareWithUserIds: number[];
  }): Promise<{ id: number }> {
    const memberIds = input.shareWithUserIds.length
      ? input.shareWithUserIds
      : input.paidByUserId
        ? [input.paidByUserId]
        : [];

    // The trip's ledger is kept in the trip's currency. Writing the dong figure
    // into it made a ten thousand dong coffee read as ten thousand dollars on a
    // USD trip — the amount is only meaningful next to its currency.
    const trip = await this.prisma.trip.findUniqueOrThrow({
      where: { id: input.tripId },
      select: { currency: true },
    });
    const usd = Number(input.amountUsdcMicro) / 1_000_000;
    const amountInTripCurrency =
      trip.currency === Currency.USD
        ? usd
        : trip.currency === Currency.VND
          ? Number(input.amountVnd)
          : Number(
              await this.exchangeRatesService.convertToHome(
                new Prisma.Decimal(usd),
                Currency.USD,
                trip.currency,
              ),
            );

    const shares = this.splitAmount(amountInTripCurrency, memberIds.length);

    return this.prisma.$transaction(async (tx) => {
      const created = await tx.expense.create({
        data: {
          tripId: input.tripId,
          paidById: input.paidByUserId ?? null,
          name: input.name,
          amount: amountInTripCurrency.toFixed(2),
          category: input.category,
          // What was really handed over, kept beside the converted figure so a
          // receipt can show the dong the merchant was paid.
          originalAmount: input.amountVnd.toString(),
          originalCurrency: Currency.VND,
          exchangeRate: input.rate ?? undefined,
        },
        select: { id: true },
      });

      if (memberIds.length) {
        await tx.expenseShare.createMany({
          data: memberIds.map((userId, index) => ({
            expenseId: created.id,
            userId,
            shareAmount: shares[index],
          })),
        });
      }

      return created;
    });
  }

  splitAmount(total: number, count: number): number[] {
    if (count <= 0) return [];
    const base = Math.floor((total * 100) / count) / 100;
    const shares = Array(count).fill(base);
    const remainder = Math.round((total - base * count) * 100) / 100;
    if (remainder > 0) {
      shares[0] = Math.round((shares[0] + remainder) * 100) / 100;
    }
    return shares;
  }
}
