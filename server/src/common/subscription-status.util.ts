// Single source of truth for "is this subscription actually live" — shared by
// subscription.service.ts and scan-credit.service.ts. Nothing in this system
// ever transitions a Google Play subscription out of ACTIVE (no Play RTDN
// endpoint is wired — /subscription/webhook only handles Apple), so
// `user.subscriptionStatus` can stay 'ACTIVE' forever after a Play sub lapses
// while `subscriptionExpiresAt` sits in the past. PR #160 first patched this
// as a read-time guard inline in subscription.service.ts; that guard was
// missing from scan-credit.service.ts's independent status check, which
// shipped a device-visible bug (a "renews Thursday" date two weeks stale).
// Lesson: guard once, here, and route every read through it.
import { SubscriptionStatus } from '@prisma/client';

export interface SubscriptionStatusFields {
  subscriptionStatus: SubscriptionStatus;
  subscriptionExpiresAt: Date | null;
}

/**
 * Resolves the effective status, collapsing a stale ACTIVE row to EXPIRED.
 *
 * Only ACTIVE is guarded: GRACE_PERIOD and BILLING_RETRY legitimately carry a
 * past `subscriptionExpiresAt` — that's the whole point of those states (the
 * store is still retrying the charge) — so a blanket expiry check would
 * revoke Pro from every user Apple/Google are still trying to bill. A NULL
 * expiry never expires (missing data must not be treated as lapsed).
 */
export function effectiveSubscriptionStatus(
  user: SubscriptionStatusFields,
): SubscriptionStatus {
  const isStaleActive =
    user.subscriptionStatus === SubscriptionStatus.ACTIVE &&
    user.subscriptionExpiresAt != null &&
    user.subscriptionExpiresAt.getTime() <= Date.now();
  return isStaleActive ? SubscriptionStatus.EXPIRED : user.subscriptionStatus;
}
