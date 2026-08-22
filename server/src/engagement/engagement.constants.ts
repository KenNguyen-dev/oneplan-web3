import { EngagementLocale, EngagementTrigger } from '@prisma/client';
import { CopyHints } from './engagement.types';

// iOS push `type` per trigger — must match the cases handled in
// NotificationDelegate.didReceive / DeepLinkRouter on the client.
export const ENGAGEMENT_PUSH_TYPE: Record<EngagementTrigger, string> = {
  UNFINISHED_PLAN: 'engagement_unfinished_plan',
  WEATHER: 'engagement_weather',
  DORMANT: 'engagement_dormant',
  NEW_PLAN_AVAILABLE: 'engagement_new_plan',
};

// The single "engine picks the best one" rule. When several triggers qualify
// for a user, the earliest in this list wins. Highest-intent / most-actionable
// first; dormant is the catch-all fallback.
export const TRIGGER_PRIORITY: EngagementTrigger[] = [
  EngagementTrigger.NEW_PLAN_AVAILABLE,
  EngagementTrigger.UNFINISHED_PLAN,
  EngagementTrigger.WEATHER,
  EngagementTrigger.DORMANT,
];

// Length caps mirrored in the LLM prompt; static templates also respect them.
export const MAX_TITLE_LEN = 40;
export const MAX_BODY_LEN = 110;

type Template = (hints: CopyHints) => { title: string; body: string };

// Static fallback copy per trigger × locale. Used whenever the LLM call fails
// or Vertex is unconfigured, so the pipeline NEVER blocks on the LLM.
// `{city}` is interpolated from hints; generic phrasing when no city is known.
export const STATIC_TEMPLATES: Record<
  EngagementTrigger,
  Record<EngagementLocale, Template>
> = {
  UNFINISHED_PLAN: {
    EN: (h) => ({
      title: 'Your plan looks empty',
      body: h.cityName
        ? `Add a few spots to your ${h.cityName} trip — it's still pretty bare.`
        : `Your trip plan is still pretty bare. Add a few spots!`,
    }),
    VN: (h) => ({
      title: 'Kế hoạch còn dang dở',
      body: h.cityName
        ? `Thêm vài địa điểm thú vị cho chuyến ${h.cityName} nhé!`
        : `Kế hoạch còn trống, tìm vài địa điểm thú vị thêm vào nhé!`,
    }),
  },
  WEATHER: {
    EN: (h) => ({
      title: h.cityName ? `Weather in ${h.cityName}` : 'Trip weather',
      body: h.cityName
        ? `It's a great day to plan something in ${h.cityName}. Check your trip!`
        : `Great weather for your trip — check your plan!`,
    }),
    VN: (h) => ({
      title: h.cityName ? `Thời tiết ở ${h.cityName}` : 'Thời tiết chuyến đi',
      body: h.cityName
        ? `${h.cityName} hôm nay hợp đi chơi lắm — xem lại kế hoạch nhé!`
        : `Thời tiết đẹp cho chuyến đi — xem lại kế hoạch nhé!`,
    }),
  },
  DORMANT: {
    EN: () => ({
      title: 'Your next trip awaits',
      body: `It's been a while! Come back and keep planning your adventure.`,
    }),
    VN: () => ({
      title: 'Chuyến đi đang chờ bạn',
      body: `Lâu rồi không gặp! Quay lại lên kế hoạch cho chuyến đi nhé.`,
    }),
  },
  NEW_PLAN_AVAILABLE: {
    EN: (h) => ({
      title: 'New plan available',
      body: h.cityName
        ? `A fresh plan for ${h.cityName} just dropped on the Market. Take a look!`
        : `A new trip plan just dropped on the Market. Take a look!`,
    }),
    VN: (h) => ({
      title: 'Có kế hoạch mới',
      body: h.cityName
        ? `Vừa có kế hoạch mới cho ${h.cityName} trên Market. Xem thử nhé!`
        : `Vừa có kế hoạch du lịch mới trên Market. Xem thử nhé!`,
    }),
  },
};

export function staticCopy(
  trigger: EngagementTrigger,
  locale: EngagementLocale,
  hints: CopyHints,
): { title: string; body: string } {
  const fn = STATIC_TEMPLATES[trigger][locale] ?? STATIC_TEMPLATES[trigger].EN;
  const out = fn(hints);
  return {
    title: out.title.slice(0, MAX_TITLE_LEN),
    body: out.body.slice(0, MAX_BODY_LEN),
  };
}
