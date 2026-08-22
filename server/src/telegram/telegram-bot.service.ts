import {
  Injectable,
  Logger,
  OnApplicationBootstrap,
  OnModuleDestroy,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AnalyticsEventName } from '@prisma/client';
import { Bot } from 'grammy';
import { AnalyticsService } from '../analytics/analytics.service';
import { TelegramCodeService } from './telegram-code.service';
import { TelegramSettingsService } from './telegram-settings.service';
import { TelegramWelcomeService } from './telegram-welcome.service';

@Injectable()
export class TelegramBotService
  implements OnApplicationBootstrap, OnModuleDestroy
{
  private readonly logger = new Logger(TelegramBotService.name);
  private bot?: Bot;

  constructor(
    private readonly config: ConfigService,
    private readonly codes: TelegramCodeService,
    private readonly welcome: TelegramWelcomeService,
    private readonly settings: TelegramSettingsService,
    private readonly analytics: AnalyticsService,
  ) {}

  get isBotEnabled(): boolean {
    return this.config.get<string>('TELEGRAM_BOT_ENABLED') === 'true';
  }

  onApplicationBootstrap(): void {
    if (!this.isBotEnabled) {
      this.logger.log('Telegram bot disabled (TELEGRAM_BOT_ENABLED != true).');
      return;
    }
    const token = this.config.get<string>('TELEGRAM_BOT_TOKEN') ?? '';
    if (!token) {
      throw new Error(
        'TELEGRAM_BOT_ENABLED=true but TELEGRAM_BOT_TOKEN is empty.',
      );
    }

    this.bot = new Bot(token);
    this.registerHandlers(this.bot);

    // Long polling. `chat_member` is NOT delivered by default — it must be
    // requested explicitly. New-member greetings ride on the `message` update
    // (new_chat_members service message), so plain `message` is enough. Do NOT
    // await — bot.start() only resolves when polling stops.
    void this.bot
      .start({
        allowed_updates: ['message'],
        onStart: (info) =>
          this.logger.log(`Telegram bot @${info.username} is polling.`),
      })
      .catch((err) => this.logger.error(`Telegram polling crashed: ${err}`));
  }

  async onModuleDestroy(): Promise<void> {
    if (!this.bot) return;
    try {
      await this.bot.stop();
      this.logger.log('Telegram bot stopped.');
    } catch (err) {
      this.logger.warn(`Telegram bot stop failed: ${(err as Error).message}`);
    }
  }

  private registerHandlers(bot: Bot): void {
    this.registerGreetingHandler(bot);
    this.registerStartHandler(bot);
  }

  // Greets each new member of the group by first name. Uses the
  // `new_chat_members` service message (delivered as a `message` update), which
  // fires reliably for normal-sized groups and isn't gated by privacy mode. A
  // single join message can list several new members (e.g. bulk add), so greet
  // each human once.
  private registerGreetingHandler(bot: Bot): void {
    bot.on('message:new_chat_members', async (ctx) => {
      const groupId = this.config.get<string>('TELEGRAM_GROUP_ID') ?? '';
      if (groupId && String(ctx.chat.id) !== groupId) return;

      const newMembers = ctx.message.new_chat_members.filter((u) => !u.is_bot);
      if (newMembers.length === 0) return;

      let resolved;
      try {
        resolved = await this.settings.resolve();
      } catch (err) {
        this.logger.warn(`Greeting failed: ${(err as Error).message}`);
        return;
      }

      // The campaign follow-up is the same for everyone in this join, so build
      // it once. Null when the campaign is off → no follow-up is sent.
      const campaign = this.welcome.buildCampaignMessage(resolved);

      for (const user of newMembers) {
        try {
          const greeting = this.welcome.buildGreeting(user, resolved);
          await ctx.reply(greeting, {
            link_preview_options: { is_disabled: true },
          });
          if (campaign) {
            await ctx.reply(campaign.text, {
              link_preview_options: { is_disabled: true },
              reply_markup: campaign.keyboard,
            });
          }
        } catch (err) {
          this.logger.warn(`Greeting failed: ${(err as Error).message}`);
        }
      }
    });
  }

  // Handles the "Get Code" deep link: /start [getcode] in the bot's private
  // chat. Hands out one offer code per Telegram user from the pool.
  private registerStartHandler(bot: Bot): void {
    bot.command('start', async (ctx) => {
      const from = ctx.from;
      if (!from) return;
      const telegramUserId = BigInt(from.id);

      // Fire-and-forget; userId/sessionId are null — Telegram users aren't
      // OnePlan users and there's no HTTP/CLS session in a poll handler.
      void this.analytics.track(AnalyticsEventName.TELEGRAM_CODE_REQUESTED, {
        userId: null,
        sessionId: null,
        properties: {
          telegramUserId: from.id,
          username: from.username ?? null,
        },
      });

      const { campaignEnabled } = await this.settings.resolve();
      if (!campaignEnabled) {
        await ctx.reply(
          'This campaign has ended — no codes are available right now. Thanks for your interest! 🙏',
        );
        void this.analytics.track(AnalyticsEventName.TELEGRAM_CODE_DENIED, {
          userId: null,
          sessionId: null,
          properties: { telegramUserId: from.id, reason: 'campaign_off' },
        });
        return;
      }

      try {
        const result = await this.codes.claimCode(
          telegramUserId,
          from.username,
        );

        if ('exhausted' in result) {
          await ctx.reply(
            'All codes have been claimed — sorry, you just missed out! 😔',
          );
          void this.analytics.track(AnalyticsEventName.TELEGRAM_CODE_DENIED, {
            userId: null,
            sessionId: null,
            properties: { telegramUserId: from.id, reason: 'exhausted' },
          });
          return;
        }

        await ctx.reply(this.buildCodeMessage(result.code), {
          parse_mode: 'HTML',
          link_preview_options: { is_disabled: true },
        });

        // Count an issuance only on a fresh assignment, not an idempotent re-tap.
        if (!result.reused) {
          void this.analytics.track(AnalyticsEventName.TELEGRAM_CODE_ISSUED, {
            userId: null,
            sessionId: null,
            properties: { telegramUserId: from.id },
          });
        }
      } catch (err) {
        this.logger.error(`claimCode failed: ${(err as Error).message}`);
        await ctx.reply(
          'Something went wrong fetching your code. Please try again in a moment.',
        );
      }
    });
  }

  private buildCodeMessage(code: string): string {
    const appleId = this.config.get<string>('APP_STORE_APP_APPLE_ID') ?? '';
    const safeCode = this.escapeHtml(code);
    const lines = [
      '🎁 Here is your OnePlan Pro offer code:',
      '',
      `<code>${safeCode}</code>`,
      '',
      'How to redeem:',
      '1. Open OnePlan and go to the subscription screen',
      '2. Tap “Have a promo code?”',
      '3. Enter the code above',
    ];
    if (appleId) {
      lines.push(
        '',
        `Or redeem directly: https://apps.apple.com/redeem?id=${appleId}&code=${encodeURIComponent(
          code,
        )}`,
      );
    }
    return lines.join('\n');
  }

  private escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }
}
