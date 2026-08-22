import { EngagementLocale } from '@prisma/client';

// Localized copy for every user-facing push notification. Mirrors the pattern
// in engagement/engagement.constants.ts (STATIC_TEMPLATES): one EN + one VN
// builder per push type, keyed by the recipient's `User.locale`. Dynamic values
// (names, trip names, message bodies) are interpolated, never translated.
//
// Vietnamese has no plural inflection, so the EN `pin`/`pins` style branches
// collapse on the VN side.

export type PushAlert = { title: string; subtitle?: string; body: string };

/** Normalize a possibly-null locale to a supported one (defaults to EN). */
export function pushLocale(locale?: EngagementLocale | null): EngagementLocale {
  return locale === EngagementLocale.VN
    ? EngagementLocale.VN
    : EngagementLocale.EN;
}

const pinFrom = (videoTitle?: string, en = true): string => {
  if (!videoTitle) return '';
  const clipped = videoTitle.slice(0, 48);
  return en ? ` from "${clipped}"` : ` từ "${clipped}"`;
};

export const PUSH_COPY = {
  friendRequest: {
    EN: (name: string): PushAlert => ({
      title: 'Friend Request',
      body: `${name} wants to be your friend`,
    }),
    VN: (name: string): PushAlert => ({
      title: 'Lời mời kết bạn',
      body: `${name} muốn kết bạn với bạn`,
    }),
  },
  friendAccepted: {
    EN: (name: string): PushAlert => ({
      title: 'Friend Request Accepted',
      body: `${name} accepted your friend request`,
    }),
    VN: (name: string): PushAlert => ({
      title: 'Đã chấp nhận lời mời kết bạn',
      body: `${name} đã chấp nhận lời mời kết bạn của bạn`,
    }),
  },
  tripRequestFulfilled: {
    EN: (destination: string): PushAlert => ({
      title: 'Your trip plan is ready',
      body: `A plan for ${destination} is now available on the Market`,
    }),
    VN: (destination: string): PushAlert => ({
      title: 'Kế hoạch chuyến đi của bạn đã sẵn sàng',
      body: `Đã có kế hoạch cho ${destination} trên Market`,
    }),
  },
  tripInvite: {
    EN: (inviter: string, tripName: string): PushAlert => ({
      title: 'Trip Invitation',
      body: `${inviter} invited you to ${tripName}`,
    }),
    VN: (inviter: string, tripName: string): PushAlert => ({
      title: 'Lời mời tham gia chuyến đi',
      body: `${inviter} đã mời bạn tham gia ${tripName}`,
    }),
  },
  // Fallback titles used only when a trip has no name (rare). Chat and the
  // trip-membership pushes otherwise use the trip name verbatim as the title.
  chatFallbackTitle: {
    EN: (): string => 'Trip Chat',
    VN: (): string => 'Trò chuyện nhóm',
  },
  tripFallbackTitle: {
    EN: (): string => 'Trip',
    VN: (): string => 'Chuyến đi',
  },
  memberLeft: {
    EN: (tripName: string, name: string): PushAlert => ({
      title: tripName,
      body: `${name} has left the trip`,
    }),
    VN: (tripName: string, name: string): PushAlert => ({
      title: tripName,
      body: `${name} đã rời khỏi chuyến đi`,
    }),
  },
  vaultLeaveAnnounced: {
    EN: (tripName: string, name: string): PushAlert => ({
      title: tripName,
      body: `${name} wants to leave — confirm settlement`,
    }),
    VN: (tripName: string, name: string): PushAlert => ({
      title: tripName,
      body: `${name} muốn rời nhóm — xác nhận quyết toán`,
    }),
  },
  memberJoined: {
    EN: (tripName: string, name: string): PushAlert => ({
      title: tripName,
      body: `${name} has joined the trip`,
    }),
    VN: (tripName: string, name: string): PushAlert => ({
      title: tripName,
      body: `${name} đã tham gia chuyến đi`,
    }),
  },
  // Plan reminder: title is the trip name (dynamic). Only the connector between
  // the item title, time and location is localized.
  planReminder: {
    EN: (
      tripName: string,
      itemTitle: string,
      startTime: string,
      location: string | null,
    ): PushAlert => ({
      title: tripName,
      body: location
        ? `${itemTitle} at ${startTime} • ${location}`
        : `${itemTitle} at ${startTime}`,
    }),
    VN: (
      tripName: string,
      itemTitle: string,
      startTime: string,
      location: string | null,
    ): PushAlert => ({
      title: tripName,
      body: location
        ? `${itemTitle} lúc ${startTime} • ${location}`
        : `${itemTitle} lúc ${startTime}`,
    }),
  },
  listingStatus: {
    EN: (listingName: string, approved: boolean): PushAlert => ({
      title: approved ? 'Listing approved' : 'Listing rejected',
      body: approved
        ? `Your listing "${listingName}" was approved.`
        : `Your listing "${listingName}" was rejected.`,
    }),
    VN: (listingName: string, approved: boolean): PushAlert => ({
      title: approved ? 'Tin đăng được duyệt' : 'Tin đăng bị từ chối',
      body: approved
        ? `Tin đăng "${listingName}" của bạn đã được duyệt.`
        : `Tin đăng "${listingName}" của bạn đã bị từ chối.`,
    }),
  },
  pinExtractionDone: {
    EN: (pinCount: number, videoTitle?: string): PushAlert => ({
      title: 'Pins ready!',
      body: `${pinCount} pin${pinCount === 1 ? '' : 's'} extracted${pinFrom(videoTitle, true)}.`,
    }),
    VN: (pinCount: number, videoTitle?: string): PushAlert => ({
      title: 'Pins đã sẵn sàng!',
      body: `Đã trích xuất ${pinCount} pin${pinFrom(videoTitle, false)}.`,
    }),
  },
  pinExtractionFailed: {
    EN: (): PushAlert => ({
      title: 'Extraction failed',
      body: "We couldn't pull pins from that video. Tap to see details.",
    }),
    VN: (): PushAlert => ({
      title: 'Trích xuất thất bại',
      body: 'Không thể lấy pin từ video đó. Chạm để xem chi tiết.',
    }),
  },
} as const;
