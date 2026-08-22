import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { SubscriptionStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ScanCreditService } from '../scan-credit/scan-credit.service';
import {
  GiftDto,
  GiftLogDto,
  GiftPackage,
  GiftResultDto,
} from './dto/gift.dto';

// Gift duration per package. Auto-renew is disabled on a gift, so this is the
// exact amount of Pro time added.
const PACKAGE_DURATION_DAYS: Record<GiftPackage, number> = {
  [GiftPackage.PRO_WEEKLY]: 7,
  [GiftPackage.PRO_MONTHLY]: 30,
  [GiftPackage.PRO_YEARLY]: 365,
};

const DAY_MS = 24 * 60 * 60 * 1000;

@Injectable()
export class GiftService {
  private readonly logger = new Logger(GiftService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly scanCredit: ScanCreditService,
  ) {}

  // Loyalty gift: grant a user free scan credits and/or a Pro package by email.
  async gift(dto: GiftDto, adminEmail: string): Promise<GiftResultDto> {
    if (!dto.scans && !dto.package) {
      throw new BadRequestException(
        'Provide at least a scan count or a package to gift.',
      );
    }

    const email = dto.email.trim().toLowerCase();
    const user = await this.prisma.user.findUnique({
      where: { email },
      select: { id: true, email: true, subscriptionExpiresAt: true },
    });
    if (!user) {
      throw new NotFoundException(`No user found with email "${dto.email}".`);
    }

    let scansGranted = 0;
    if (dto.scans && dto.scans > 0) {
      await this.scanCredit.adminAdjust(
        user.id,
        dto.scans,
        `gift by ${adminEmail}`,
      );
      scansGranted = dto.scans;
    }

    let subscriptionExpiresAt: string | null = null;
    if (dto.package) {
      const days = PACKAGE_DURATION_DAYS[dto.package];
      // Extend from the later of now / current expiry so a gift never shortens
      // an existing Pro subscription.
      const base =
        user.subscriptionExpiresAt && user.subscriptionExpiresAt > new Date()
          ? user.subscriptionExpiresAt.getTime()
          : Date.now();
      const expiresAt = new Date(base + days * DAY_MS);
      await this.prisma.user.update({
        where: { id: user.id },
        data: {
          subscriptionStatus: SubscriptionStatus.ACTIVE,
          subscriptionProductId: dto.package,
          subscriptionExpiresAt: expiresAt,
          autoRenewEnabled: false,
        },
      });
      subscriptionExpiresAt = expiresAt.toISOString();
    }

    // Human-readable audit row for the admin "Gift" history.
    await this.prisma.giftLog.create({
      data: {
        recipientUserId: user.id,
        recipientEmail: user.email,
        adminEmail,
        scans: scansGranted,
        package: dto.package ?? null,
        subscriptionExpiresAt: subscriptionExpiresAt
          ? new Date(subscriptionExpiresAt)
          : null,
      },
    });

    this.logger.log(
      `Gift by ${adminEmail} to ${user.email}: ${scansGranted} scans` +
        (dto.package
          ? `, package ${dto.package} until ${subscriptionExpiresAt}`
          : ''),
    );

    return {
      userId: user.id,
      email: user.email,
      scansGranted,
      packageGranted: dto.package ?? null,
      subscriptionExpiresAt,
    };
  }

  // Recent gift history, newest first.
  async listGifts(limit = 50): Promise<GiftLogDto[]> {
    const rows = await this.prisma.giftLog.findMany({
      orderBy: { createdAt: 'desc' },
      take: Math.min(Math.max(limit, 1), 200),
    });
    return rows.map((r) => ({
      id: r.id,
      recipientUserId: r.recipientUserId,
      recipientEmail: r.recipientEmail,
      adminEmail: r.adminEmail,
      scans: r.scans,
      package: r.package,
      subscriptionExpiresAt: r.subscriptionExpiresAt
        ? r.subscriptionExpiresAt.toISOString()
        : null,
      createdAt: r.createdAt.toISOString(),
    }));
  }
}
