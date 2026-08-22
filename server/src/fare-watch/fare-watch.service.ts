import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { FareWatchStatus } from '@prisma/client';
import { createHash, randomInt } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { ZnsService } from '../common/zalo/zns.service';
import { FarePrice, TravelpayoutsService } from './travelpayouts.service';
import {
  CreateFareWatchOrderDto,
  VerifyFareWatchOrderDto,
} from './dto/create-fare-watch-order.dto';

// Guest quota: a phone number is the identity, so cap ACTIVE orders per phone.
const MAX_ACTIVE_PER_PHONE = 5;
const OTP_TTL_MS = 5 * 60_000;
const MAX_OTP_ATTEMPTS = 5;
// Public fares board: cached per route so the landing page never hammers
// Travelpayouts (their data refreshes on the order of hours anyway).
const FARES_TTL_MS = 30 * 60_000;
const FARES_MONTHS_AHEAD = 2;

function hashOtp(otp: string, publicId: string): string {
  return createHash('sha256').update(`${publicId}:${otp}`).digest('hex');
}

@Injectable()
export class FareWatchService {
  private readonly logger = new Logger(FareWatchService.name);

  private readonly faresCache = new Map<
    string,
    { at: number; fares: FarePrice[] }
  >();

  constructor(
    private readonly prisma: PrismaService,
    private readonly zns: ZnsService,
    private readonly tp: TravelpayoutsService,
    private readonly config: ConfigService,
  ) {}

  // Public fares board for the /radar landing: real cached Travelpayouts
  // prices (cheapest per departure date) so the page never shows invented
  // numbers. Cached per route; an empty list means "no data", the page is
  // expected to degrade honestly instead of fabricating fares.
  async fares(origin: string, destination: string) {
    const o = origin.toUpperCase();
    const d = destination.toUpperCase();
    if (!/^[A-Z]{3}$/.test(o) || !/^[A-Z]{3}$/.test(d) || o === d) {
      throw new BadRequestException('origin/destination must be IATA codes');
    }
    const key = `${o}-${d}`;
    const hit = this.faresCache.get(key);
    if (hit && Date.now() - hit.at < FARES_TTL_MS) {
      return { updatedAt: new Date(hit.at).toISOString(), fares: hit.fares };
    }
    const today = new Date();
    const fares: FarePrice[] = [];
    for (let m = 0; m < FARES_MONTHS_AHEAD; m++) {
      const month = new Date(today.getFullYear(), today.getMonth() + m, 1);
      const ym = `${month.getFullYear()}-${String(month.getMonth() + 1).padStart(2, '0')}`;
      fares.push(...(await this.tp.pricesForMonth(o, d, ym)));
    }
    const todayIso = today.toISOString().slice(0, 10);
    // Cheapest fare per departure date: the source returns many fares per
    // day, the board wants one honest floor price per day.
    const bestByDate = new Map<string, FarePrice>();
    for (const f of fares) {
      if (f.departDate < todayIso) continue;
      const cur = bestByDate.get(f.departDate);
      if (!cur || f.price < cur.price) bestByDate.set(f.departDate, f);
    }
    const upcoming = [...bestByDate.values()].sort((a, b) =>
      a.departDate.localeCompare(b.departDate),
    );
    this.faresCache.set(key, { at: Date.now(), fares: upcoming });
    return { updatedAt: new Date().toISOString(), fares: upcoming };
  }

  // Guest flow: create PAUSED order + send OTP over ZNS; the order only goes
  // ACTIVE after verify. App flow (userId given): ACTIVE immediately, alerts
  // ride the existing push channel.
  async create(dto: CreateFareWatchOrderDto, userId?: number) {
    const origin = dto.origin.toUpperCase();
    const destination = dto.destination.toUpperCase();
    if (origin === destination) {
      throw new BadRequestException('Origin and destination must differ');
    }
    const dateFrom = new Date(dto.dateFrom);
    const dateTo = new Date(dto.dateTo);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    if (!(dateFrom <= dateTo)) {
      throw new BadRequestException('dateFrom must be before dateTo');
    }
    if (dateTo < today) {
      throw new BadRequestException('Travel window is already in the past');
    }
    if (!userId && !dto.phone) {
      throw new BadRequestException('Guests must provide a phone number');
    }

    const phone = dto.phone?.replace(/^84/, '0');
    if (phone) {
      const active = await this.prisma.fareWatchOrder.count({
        where: {
          phone,
          status: { in: [FareWatchStatus.ACTIVE, FareWatchStatus.PAUSED] },
        },
      });
      if (active >= MAX_ACTIVE_PER_PHONE) {
        throw new HttpException(
          `This phone already has ${MAX_ACTIVE_PER_PHONE} watches; cancel one first`,
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }
    }

    const isGuest = !userId;
    // Watch dies at the end of the travel window: nothing to hunt after that.
    const expiresAt = new Date(dateTo);
    expiresAt.setHours(23, 59, 59, 0);

    const order = await this.prisma.fareWatchOrder.create({
      data: {
        userId: userId ?? null,
        name: dto.name?.trim().slice(0, 60) || null,
        phone: phone ?? null,
        phoneVerified: !isGuest,
        origin,
        destination,
        dateFrom,
        dateTo,
        targetPrice: dto.targetPrice,
        tripId: dto.tripId ?? null,
        channel: isGuest ? 'ZNS' : 'PUSH',
        status: isGuest ? FareWatchStatus.PAUSED : FareWatchStatus.ACTIVE,
        expiresAt,
      },
    });

    if (isGuest) {
      const otp = randomInt(1000, 10000).toString();
      await this.prisma.fareWatchOrder.update({
        where: { id: order.id },
        data: {
          otpHash: hashOtp(otp, order.publicId),
          otpExpiresAt: new Date(Date.now() + OTP_TTL_MS),
          otpAttempts: 0,
        },
      });
      const templateId = this.config.get<string>('ZNS_OTP_TEMPLATE_ID') ?? '';
      const sent = await this.zns.send(phone as string, templateId, {
        otp,
      });
      if (!sent.ok) {
        // Without a delivered OTP the guest can never activate: fail loudly so
        // the web falls back to its demo mode instead of stranding the user.
        await this.prisma.fareWatchOrder.delete({ where: { id: order.id } });
        this.logger.warn(
          `OTP send failed for ${order.publicId}: ${sent.error}`,
        );
        throw new ServiceUnavailableException('Could not deliver OTP');
      }
    }

    return {
      publicId: order.publicId,
      status: order.status,
      needsOtp: isGuest,
    };
  }

  async verify(dto: VerifyFareWatchOrderDto) {
    const order = await this.prisma.fareWatchOrder.findUnique({
      where: { publicId: dto.publicId },
    });
    if (!order || !order.otpHash) {
      throw new NotFoundException('Order not found or not awaiting OTP');
    }
    if (order.otpAttempts >= MAX_OTP_ATTEMPTS) {
      throw new BadRequestException('Too many attempts; create a new order');
    }
    if (!order.otpExpiresAt || order.otpExpiresAt < new Date()) {
      throw new BadRequestException('OTP expired; create a new order');
    }
    if (hashOtp(dto.otp, order.publicId) !== order.otpHash) {
      await this.prisma.fareWatchOrder.update({
        where: { id: order.id },
        data: { otpAttempts: { increment: 1 } },
      });
      throw new BadRequestException('Wrong OTP');
    }
    const updated = await this.prisma.fareWatchOrder.update({
      where: { id: order.id },
      data: {
        phoneVerified: true,
        status: FareWatchStatus.ACTIVE,
        otpHash: null,
        otpExpiresAt: null,
      },
    });
    return {
      publicId: updated.publicId,
      status: updated.status,
      code: `RD-${updated.publicId.slice(-5).toUpperCase()}`,
    };
  }

  async get(publicId: string) {
    const order = await this.prisma.fareWatchOrder.findUnique({
      where: { publicId },
      select: {
        publicId: true,
        origin: true,
        destination: true,
        dateFrom: true,
        dateTo: true,
        targetPrice: true,
        status: true,
        notifyCount: true,
        lastNotifiedAt: true,
        createdAt: true,
      },
    });
    if (!order) throw new NotFoundException('Order not found');
    return order;
  }

  async cancel(publicId: string) {
    const order = await this.prisma.fareWatchOrder.findUnique({
      where: { publicId },
    });
    if (!order) throw new NotFoundException('Order not found');
    await this.prisma.fareWatchOrder.update({
      where: { id: order.id },
      data: { status: FareWatchStatus.CANCELLED },
    });
    return { publicId, status: FareWatchStatus.CANCELLED };
  }
}
