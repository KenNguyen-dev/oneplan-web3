import { FareWatchStatus } from '@prisma/client';
import { decideAlert } from './fare-watch-engine.service';

// decideAlert is the money function: every guardrail that keeps Radar from
// spamming (or ghosting) users lives here, so every branch gets a test.

const NOON = new Date('2026-08-01T12:00:00+07:00');
const VN_NOON = 12;

function order(over: Partial<Parameters<typeof decideAlert>[0]> = {}) {
  return {
    status: FareWatchStatus.ACTIVE,
    targetPrice: 1_000_000,
    expiresAt: new Date('2026-08-31T23:59:59+07:00'),
    lastNotifiedAt: null,
    lastNotifiedPrice: null,
    notifyCount: 0,
    ...over,
  };
}

describe('decideAlert', () => {
  it('sends when price hits target on a fresh order', () => {
    expect(decideAlert(order(), 900_000, NOON, VN_NOON, 0).send).toBe(true);
  });

  it('does not send above target', () => {
    const d = decideAlert(order(), 1_000_001, NOON, VN_NOON, 0);
    expect(d).toEqual({ send: false, reason: 'above target' });
  });

  it('sends at exactly the target price', () => {
    expect(decideAlert(order(), 1_000_000, NOON, VN_NOON, 0).send).toBe(true);
  });

  it.each([
    ['PAUSED', FareWatchStatus.PAUSED],
    ['CANCELLED', FareWatchStatus.CANCELLED],
    ['EXPIRED', FareWatchStatus.EXPIRED],
  ])('never sends for %s orders', (_n, status) => {
    expect(decideAlert(order({ status }), 1, NOON, VN_NOON, 0).send).toBe(
      false,
    );
  });

  it('never sends after the travel window closed', () => {
    const d = decideAlert(
      order({ expiresAt: new Date('2026-07-01') }),
      1,
      NOON,
      VN_NOON,
      0,
    );
    expect(d.reason).toBe('expired');
  });

  describe('quiet hours (Asia/Ho_Chi_Minh)', () => {
    it.each([22, 23, 0, 3, 6])('holds at %i:00 VN', (h) => {
      expect(decideAlert(order(), 1, NOON, h, 0).reason).toBe('quiet hours');
    });
    it.each([7, 12, 21])('sends at %i:00 VN', (h) => {
      expect(decideAlert(order(), 1, NOON, h, 0).send).toBe(true);
    });
  });

  describe('rate caps', () => {
    it('holds at 2 alerts already today', () => {
      expect(decideAlert(order(), 1, NOON, VN_NOON, 2).reason).toBe(
        'daily cap',
      );
    });
    it('holds at 20 lifetime alerts', () => {
      expect(
        decideAlert(order({ notifyCount: 20 }), 1, NOON, VN_NOON, 0).reason,
      ).toBe('lifetime cap');
    });
  });

  describe('cooldown', () => {
    const recentlyNotified = order({
      lastNotifiedAt: new Date(NOON.getTime() - 2 * 60 * 60_000), // 2h ago
      lastNotifiedPrice: 950_000,
      notifyCount: 1,
    });

    it('holds inside 24h for a similar price', () => {
      expect(
        decideAlert(recentlyNotified, 940_000, NOON, VN_NOON, 1).reason,
      ).toBe('cooldown');
    });

    it('breaks cooldown when the price drops another 7%', () => {
      // 950k * 0.93 = 883.5k
      expect(
        decideAlert(recentlyNotified, 883_000, NOON, VN_NOON, 1).send,
      ).toBe(true);
    });

    it('sends again after 24h', () => {
      const old = order({
        lastNotifiedAt: new Date(NOON.getTime() - 25 * 60 * 60_000),
        lastNotifiedPrice: 950_000,
        notifyCount: 1,
      });
      expect(decideAlert(old, 940_000, NOON, VN_NOON, 0).send).toBe(true);
    });
  });
});
