import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron } from '@nestjs/schedule';
import { FareWatchOrder, FareWatchStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ZnsService } from '../common/zalo/zns.service';
import { FarePrice, TravelpayoutsService } from './travelpayouts.service';

// The price engine: sweeps cached fares for every route that has ACTIVE
// watches, and pings the owner over Zalo ZNS when a fare crosses their
// target. Design rule inherited from the spec: ONE wrong alert costs more
// trust than ten missed ones, so every send passes a fresh verify fetch and
// hard rate caps.
//
// v1 scope: ZNS only. PUSH-channel orders (app users) are matched and logged
// but not pushed yet; the app flow ships in a later phase.

const HOT_ROUTE_MIN_ORDERS = 20;
const HOT_INTERVAL_MS = 2 * 60 * 60_000;
const NORMAL_INTERVAL_MS = 6 * 60 * 60_000;
const COOLDOWN_MS = 24 * 60 * 60_000;
const REALERT_DROP = 0.07; // re-alert inside cooldown only if 7% cheaper
const MAX_ALERTS_PER_DAY = 2;
const MAX_ALERTS_LIFETIME = 20;
const VERIFY_DRIFT_LIMIT = 0.1; // cached vs verify >10% apart -> suppress
const QUIET_START_HOUR = 22; // Asia/Ho_Chi_Minh
const QUIET_END_HOUR = 7;

export interface AlertDecision {
  send: boolean;
  reason: string;
}

// Pure decision function, unit-tested in isolation. `now` is injected so the
// tests never touch the clock.
export function decideAlert(
  order: Pick<
    FareWatchOrder,
    | 'status'
    | 'targetPrice'
    | 'expiresAt'
    | 'lastNotifiedAt'
    | 'lastNotifiedPrice'
    | 'notifyCount'
  >,
  price: number,
  now: Date,
  vnHour: number,
  alertsToday: number,
): AlertDecision {
  if (order.status !== FareWatchStatus.ACTIVE) {
    return { send: false, reason: 'not active' };
  }
  if (order.expiresAt < now) return { send: false, reason: 'expired' };
  if (!order.targetPrice || price > order.targetPrice) {
    return { send: false, reason: 'above target' };
  }
  if (vnHour >= QUIET_START_HOUR || vnHour < QUIET_END_HOUR) {
    return { send: false, reason: 'quiet hours' };
  }
  if (order.notifyCount >= MAX_ALERTS_LIFETIME) {
    return { send: false, reason: 'lifetime cap' };
  }
  if (alertsToday >= MAX_ALERTS_PER_DAY) {
    return { send: false, reason: 'daily cap' };
  }
  if (order.lastNotifiedAt) {
    const inCooldown =
      now.getTime() - order.lastNotifiedAt.getTime() < COOLDOWN_MS;
    const bigDrop =
      order.lastNotifiedPrice != null &&
      price <= order.lastNotifiedPrice * (1 - REALERT_DROP);
    if (inCooldown && !bigDrop) {
      return { send: false, reason: 'cooldown' };
    }
  }
  return { send: true, reason: 'target hit' };
}

function vnHour(now: Date): number {
  return parseInt(
    new Intl.DateTimeFormat('en-GB', {
      hour: '2-digit',
      hour12: false,
      timeZone: 'Asia/Ho_Chi_Minh',
    }).format(now),
    10,
  );
}

function fmtVnd(n: number): string {
  return n.toLocaleString('vi-VN');
}

function fmtDateVn(iso: string): string {
  const [y, m, d] = iso.split('-');
  return `${d}/${m}/${y}`;
}

@Injectable()
export class FareWatchEngineService {
  private readonly logger = new Logger(FareWatchEngineService.name);
  private running = false;
  private lastSweepAt = new Map<string, number>(); // route -> epoch ms

  constructor(
    private readonly prisma: PrismaService,
    private readonly tp: TravelpayoutsService,
    private readonly zns: ZnsService,
    private readonly config: ConfigService,
  ) {}

  private get enabled(): boolean {
    // Engine needs a price source; alerting additionally needs the approved
    // ZNS template. Sweeping without the template still collects history.
    return (
      this.tp.enabled &&
      (this.config.get<string>('FARE_WATCH_ENGINE_ENABLED') ?? 'true') !==
        'false'
    );
  }

  // Every 30 minutes decide which routes are due (hot: 2h, normal: 6h).
  @Cron('*/30 * * * *')
  async tick(): Promise<void> {
    if (!this.enabled || this.running) return;
    this.running = true;
    try {
      await this.expireDeadOrders();
      const groups = await this.dueRouteGroups();
      for (const g of groups) {
        await this.sweepGroup(g.origin, g.destination, g.months, g.orders);
      }
    } catch (e) {
      this.logger.error(`tick failed: ${(e as Error).message}`);
    } finally {
      this.running = false;
    }
  }

  private async expireDeadOrders(): Promise<void> {
    await this.prisma.fareWatchOrder.updateMany({
      where: {
        status: { in: [FareWatchStatus.ACTIVE, FareWatchStatus.PAUSED] },
        expiresAt: { lt: new Date() },
      },
      data: { status: FareWatchStatus.EXPIRED },
    });
  }

  // ACTIVE orders grouped by route; a route is swept when its interval (hot
  // or normal) has elapsed since the previous sweep.
  private async dueRouteGroups(): Promise<
    {
      origin: string;
      destination: string;
      months: string[];
      orders: FareWatchOrder[];
    }[]
  > {
    const orders = await this.prisma.fareWatchOrder.findMany({
      where: { status: FareWatchStatus.ACTIVE },
    });
    const byRoute = new Map<string, FareWatchOrder[]>();
    for (const o of orders) {
      const key = `${o.origin}-${o.destination}`;
      byRoute.set(key, [...(byRoute.get(key) ?? []), o]);
    }
    const now = Date.now();
    const due: {
      origin: string;
      destination: string;
      months: string[];
      orders: FareWatchOrder[];
    }[] = [];
    for (const [route, routeOrders] of byRoute) {
      const interval =
        routeOrders.length >= HOT_ROUTE_MIN_ORDERS
          ? HOT_INTERVAL_MS
          : NORMAL_INTERVAL_MS;
      if (now - (this.lastSweepAt.get(route) ?? 0) < interval) continue;
      this.lastSweepAt.set(route, now);
      const [origin, destination] = route.split('-');
      const months = new Set<string>();
      for (const o of routeOrders) {
        // Every month the watch window touches.
        const from = new Date(o.dateFrom);
        const to = new Date(o.dateTo);
        for (
          let d = new Date(from);
          d <= to;
          d = new Date(d.getFullYear(), d.getMonth() + 1, 1)
        ) {
          months.add(d.toISOString().slice(0, 7));
        }
      }
      due.push({
        origin,
        destination,
        months: [...months],
        orders: routeOrders,
      });
    }
    return due;
  }

  private async sweepGroup(
    origin: string,
    destination: string,
    months: string[],
    orders: FareWatchOrder[],
  ): Promise<void> {
    const prices: FarePrice[] = [];
    for (const month of months) {
      prices.push(
        ...(await this.tp.pricesForMonth(origin, destination, month)),
      );
    }
    if (prices.length === 0) return;

    // Append price history (powers future sparklines + p25 suggestions).
    await this.prisma.fareQuote.createMany({
      data: prices.map((p) => ({
        origin,
        destination,
        departDate: new Date(p.departDate),
        airline: p.airline,
        price: p.price,
        source: 'travelpayouts',
        deepLink: p.link,
      })),
    });

    for (const order of orders) {
      const inWindow = prices.filter(
        (p) =>
          new Date(p.departDate) >= order.dateFrom &&
          new Date(p.departDate) <= order.dateTo,
      );
      if (inWindow.length === 0) continue;
      const best = inWindow.reduce((a, b) => (a.price <= b.price ? a : b));
      await this.maybeAlert(order, best);
    }
  }

  private async maybeAlert(
    order: FareWatchOrder,
    cached: FarePrice,
  ): Promise<void> {
    const now = new Date();
    const dayStart = new Date(now);
    dayStart.setHours(0, 0, 0, 0);
    const alertsToday = await this.prisma.fareAlertLog.count({
      where: { orderId: order.id, sentAt: { gte: dayStart } },
    });
    const decision = decideAlert(
      order,
      cached.price,
      now,
      vnHour(now),
      alertsToday,
    );
    if (!decision.send) return;

    // Verify pass: fresh fetch for the exact date. Drift beyond 10% means the
    // cached deal is stale -> suppress and record the drift (this number is
    // the project's go/no-go metric).
    const fresh = await this.tp.priceForDate(
      order.origin,
      order.destination,
      cached.departDate,
    );
    if (!fresh) {
      this.logger.warn(
        `verify miss ${order.publicId} ${cached.departDate}: deal gone`,
      );
      return;
    }
    const drift = Math.abs(fresh.price - cached.price) / cached.price;
    if (drift > VERIFY_DRIFT_LIMIT) {
      this.logger.warn(
        `verify drift ${(drift * 100).toFixed(1)}% ${order.publicId}: suppress`,
      );
      return;
    }
    if (order.targetPrice && fresh.price > order.targetPrice) {
      this.logger.log(`verify price above target ${order.publicId}: suppress`);
      return;
    }

    await this.sendAlert(order, fresh);
  }

  private async sendAlert(
    order: FareWatchOrder,
    price: FarePrice,
  ): Promise<void> {
    const quote = await this.prisma.fareQuote.create({
      data: {
        origin: order.origin,
        destination: order.destination,
        departDate: new Date(price.departDate),
        airline: price.airline,
        price: price.price,
        source: 'travelpayouts-verified',
        deepLink: price.link,
      },
    });
    const log = await this.prisma.fareAlertLog.create({
      data: {
        orderId: order.id,
        quoteId: quote.id,
        price: price.price,
        channel: order.channel,
        status: 'PENDING',
      },
    });

    // v1: ZNS only. PUSH orders are logged as SKIPPED until the app flow ships.
    if (!order.phone) {
      await this.prisma.fareAlertLog.update({
        where: { id: log.id },
        data: { status: 'SKIPPED' },
      });
      return;
    }
    const templateId = this.config.get<string>('ZNS_ALERT_TEMPLATE_ID') ?? '';
    const sent = await this.zns.send(
      order.phone,
      templateId,
      {
        // Param names/formats mirror the ZBS template. The ZBS button-link
        // field only accepts a FIXED https URL with params embedded in the
        // query, so the buttons are configured as:
        //   https://www.oneplan.space/book?r=<book_ref>
        //   https://www.oneplan.space/radar?o=<order_id>
        // book_ref is a dot-joined token the /book page parses:
        // <logId>.<origin>.<dest>.<departDate>.<publicId> (cuid has no dots).
        // Zalo review also requires customer-identification pairs with
        // labeled prefixes in the body ("Chào <customer_name>", "Mã lệnh
        // <order_code>"). Orders without a stored name fall back to "bạn" so
        // the sentence still reads naturally ("Chào bạn").
        customer_name: order.name?.trim() || 'bạn',
        order_code: `RD-${order.publicId.slice(-5).toUpperCase()}`,
        route: `${order.origin}-${order.destination}`,
        flight_date: fmtDateVn(price.departDate),
        price: fmtVnd(price.price),
        target_price: fmtVnd(order.targetPrice ?? price.price),
        book_ref: `${log.id}.${order.origin}.${order.destination}.${price.departDate.slice(0, 10)}.${order.publicId}`,
        order_id: order.publicId,
      },
      `fare-alert-${log.id}`,
    );

    await this.prisma.fareAlertLog.update({
      where: { id: log.id },
      data: {
        status: sent.ok ? 'SENT' : 'FAILED',
        znsMsgId: sent.msgId ?? null,
      },
    });
    if (sent.ok) {
      // Stays ACTIVE on purpose: the fare can keep dropping until the travel
      // window closes, and cooldown/7%-drop rules already throttle re-alerts.
      await this.prisma.fareWatchOrder.update({
        where: { id: order.id },
        data: {
          lastNotifiedAt: new Date(),
          lastNotifiedPrice: price.price,
          notifyCount: { increment: 1 },
        },
      });
      this.logger.log(
        `alert sent ${order.publicId}: ${order.origin}-${order.destination} ${fmtVnd(price.price)}d`,
      );
    } else {
      this.logger.warn(`alert send failed ${order.publicId}: ${sent.error}`);
    }
  }
}
