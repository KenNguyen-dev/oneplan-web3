import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';

// Default bilingual (EN + VI) community greeting. `{name}` is replaced with the
// new member's first name. Overridable from the admin page (or TELEGRAM_WELCOME_TEXT).
export const DEFAULT_WELCOME_TEXT = `👋 Welcome {name} to OnePlan Travel!

We’re happy to have you here.
This is the official community for OnePlan Travel — a place to explore smarter group travel planning, shared budgets, trip ideas, and updates from our team.

Feel free to say hi, ask questions, share feedback, or drop your travel ideas with us.
Let’s plan less and trip more. ✈️

——

👋 Chào mừng {name} đến với OnePlan Travel!

Rất vui khi có bạn trong cộng đồng của tụi mình.
Đây là group chính thức của OnePlan Travel - nơi chia sẻ về lập kế hoạch du lịch nhóm, quản lý chi phí chung, ý tưởng chuyến đi và các cập nhật mới từ team.

Bạn có thể chào mọi người, đặt câu hỏi, góp ý hoặc chia sẻ những ý tưởng du lịch cùng tụi mình nha.
Cùng nhau plan ít hơn, đi vui hơn. ✈️`;

// Shown below the greeting only during the campaign (EN + VI), right above the
// "Get Code" button. Overridable from the admin page (or TELEGRAM_CAMPAIGN_CTA).
export const DEFAULT_CAMPAIGN_CTA = `🎁 OnePlan Travel is giving you 3 months free!
Tap the link below to get your code and unlock 3 months of OnePlan Pro.

——

🎁 OnePlan Travel tặng bạn 3 tháng sử dụng miễn phí!
Bấm vào link dưới đây để nhận mã và mở khóa 3 tháng OnePlan Pro.`;

export interface ResolvedTelegramSettings {
  campaignEnabled: boolean;
  welcomeText: string;
  cta: string;
  // From env (bot identity) — not editable from the admin page, but needed to
  // build the deep-link button.
  botUsername: string;
}

const KEY_CAMPAIGN_ENABLED = 'campaign_enabled';
const KEY_WELCOME_TEXT = 'welcome_text';
const KEY_CAMPAIGN_CTA = 'campaign_cta';

// Short safety-net TTL. The cache is busted on every write, so this only
// matters in the (currently impossible) multi-process case.
const CACHE_TTL_MS = 60_000;

// Resolves the editable Telegram campaign settings with precedence:
//   DB value (set from the admin page)  >  env default  >  baked-in constant.
// Stored as a tiny key/value table; the campaign flag is persisted as the
// strings 'true'/'false' to match the env-flag convention.
@Injectable()
export class TelegramSettingsService {
  private cache: Map<string, string> | null = null;
  private cachedAt = 0;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async resolve(): Promise<ResolvedTelegramSettings> {
    const rows = await this.load();
    const dbCampaign = rows.get(KEY_CAMPAIGN_ENABLED);
    const campaignEnabled =
      dbCampaign != null
        ? dbCampaign === 'true'
        : this.config.get<string>('TELEGRAM_CAMPAIGN_ENABLED') === 'true';

    return {
      campaignEnabled,
      welcomeText:
        rows.get(KEY_WELCOME_TEXT) ||
        this.config.get<string>('TELEGRAM_WELCOME_TEXT') ||
        DEFAULT_WELCOME_TEXT,
      cta:
        rows.get(KEY_CAMPAIGN_CTA) ||
        this.config.get<string>('TELEGRAM_CAMPAIGN_CTA') ||
        DEFAULT_CAMPAIGN_CTA,
      // Strip a leading '@' so both '@oneplan_code_bot' and 'oneplan_code_bot'
      // produce a valid t.me/<name> deep link.
      botUsername: (
        this.config.get<string>('TELEGRAM_BOT_USERNAME') ?? ''
      ).replace(/^@/, ''),
    };
  }

  async update(input: {
    campaignEnabled?: boolean;
    welcomeText?: string;
    cta?: string;
  }): Promise<ResolvedTelegramSettings> {
    const writes: { key: string; value: string }[] = [];
    if (input.campaignEnabled !== undefined) {
      writes.push({
        key: KEY_CAMPAIGN_ENABLED,
        value: input.campaignEnabled ? 'true' : 'false',
      });
    }
    if (input.welcomeText !== undefined) {
      writes.push({ key: KEY_WELCOME_TEXT, value: input.welcomeText });
    }
    if (input.cta !== undefined) {
      writes.push({ key: KEY_CAMPAIGN_CTA, value: input.cta });
    }

    for (const w of writes) {
      await this.prisma.telegramSetting.upsert({
        where: { key: w.key },
        create: w,
        update: { value: w.value },
      });
    }

    this.cache = null; // bust so the next resolve() reflects the write
    return this.resolve();
  }

  private async load(): Promise<Map<string, string>> {
    const now = Date.now();
    if (this.cache && now - this.cachedAt < CACHE_TTL_MS) return this.cache;
    const rows = await this.prisma.telegramSetting.findMany();
    this.cache = new Map(rows.map((r) => [r.key, r.value]));
    this.cachedAt = now;
    return this.cache;
  }
}
