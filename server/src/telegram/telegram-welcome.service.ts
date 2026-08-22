import { Injectable } from '@nestjs/common';
import { InlineKeyboard } from 'grammy';
import type { ResolvedTelegramSettings } from './telegram-settings.service';

// The "Get Code" button is a deep link into the bot. Tapping it opens a private
// chat with the bot; once the user presses Start, the bot receives
// `/start getcode` and DMs them a code.
const START_PAYLOAD = 'getcode';

export interface GreetingUser {
  first_name?: string;
  username?: string;
}

// The campaign call-to-action, sent as a SEPARATE follow-up message after the
// greeting. Carries the "Get Code" button.
export interface CampaignMessage {
  text: string;
  keyboard: InlineKeyboard;
}

@Injectable()
export class TelegramWelcomeService {
  // First name preferred (friendliest, always present), then @username, then a
  // neutral fallback.
  resolveName(user: GreetingUser): string {
    return user.first_name?.trim() || user.username?.trim() || 'there';
  }

  // The greeting message, sent to EVERY new member regardless of campaign state.
  buildGreeting(
    user: GreetingUser,
    settings: ResolvedTelegramSettings,
  ): string {
    const name = this.resolveName(user);
    // Plain-text send (no parse_mode), so the interpolated name needs no escaping.
    return settings.welcomeText.split('{name}').join(name);
  }

  // The follow-up campaign message (CTA + Get Code button), or null when the
  // campaign is off. The CTA says "tap the link below", so it only makes sense
  // with the button — both are gated on the campaign flag AND a configured bot
  // username for the deep link. When the campaign ends, no follow-up is sent.
  buildCampaignMessage(
    settings: ResolvedTelegramSettings,
  ): CampaignMessage | null {
    if (!settings.campaignEnabled || !settings.botUsername) return null;
    return {
      text: settings.cta,
      keyboard: new InlineKeyboard().url(
        'Get Code',
        `https://t.me/${settings.botUsername}?start=${START_PAYLOAD}`,
      ),
    };
  }
}
