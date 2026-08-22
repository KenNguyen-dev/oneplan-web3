import { TelegramWelcomeService } from './telegram-welcome.service';
import {
  DEFAULT_CAMPAIGN_CTA,
  DEFAULT_WELCOME_TEXT,
  type ResolvedTelegramSettings,
} from './telegram-settings.service';

const base: ResolvedTelegramSettings = {
  campaignEnabled: false,
  welcomeText: DEFAULT_WELCOME_TEXT,
  cta: DEFAULT_CAMPAIGN_CTA,
  botUsername: 'oneplan_bot',
};

describe('TelegramWelcomeService', () => {
  const service = new TelegramWelcomeService();

  describe('resolveName', () => {
    it('prefers first name, then username, then a fallback', () => {
      expect(service.resolveName({ first_name: 'khanh', username: 'k' })).toBe(
        'khanh',
      );
      expect(service.resolveName({ username: 'k' })).toBe('k');
      expect(service.resolveName({})).toBe('there');
    });
  });

  describe('buildGreeting', () => {
    it('greets by name and never contains the campaign CTA', () => {
      const off = service.buildGreeting({ first_name: 'khanh' }, base);
      expect(off).toContain('Welcome khanh to OnePlan Travel');
      expect(off).toContain('Chào mừng khanh'); // bilingual
      expect(off).not.toContain('3 months free');

      // Identical greeting regardless of campaign state — the CTA is separate.
      const on = service.buildGreeting(
        { first_name: 'khanh' },
        { ...base, campaignEnabled: true },
      );
      expect(on).toBe(off);
    });

    it('substitutes a custom welcome template containing {name}', () => {
      const text = service.buildGreeting(
        { first_name: 'khanh' },
        { ...base, welcomeText: 'Hi {name}!' },
      );
      expect(text).toBe('Hi khanh!');
    });
  });

  describe('buildCampaignMessage', () => {
    it('returns null when the campaign is off', () => {
      expect(service.buildCampaignMessage(base)).toBeNull();
    });

    it('returns null when the campaign is on but no bot username is set', () => {
      expect(
        service.buildCampaignMessage({
          ...base,
          campaignEnabled: true,
          botUsername: '',
        }),
      ).toBeNull();
    });

    it('returns the CTA text + deep-link button when the campaign is on', () => {
      const msg = service.buildCampaignMessage({
        ...base,
        campaignEnabled: true,
      });
      expect(msg).not.toBeNull();
      expect(msg!.text).toContain('3 months free');
      expect(msg!.text).toContain('3 tháng sử dụng miễn phí');
      expect(JSON.stringify(msg!.keyboard)).toContain(
        'https://t.me/oneplan_bot?start=getcode',
      );
    });
  });
});
