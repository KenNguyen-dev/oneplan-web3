import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';

// Zalo Notification Service (ZNS) sender for the OnePlan Official Account.
//
// OAuth quirk this service exists to absorb: Zalo ROTATES the refresh token on
// every refresh call. Reusing an old refresh token kills the whole grant, so
// the freshest pair is persisted in the single-row ZaloOauthToken table and
// the env var ZALO_OA_REFRESH_TOKEN is only the BOOTSTRAP value for the very
// first refresh after deploy.
//
// Env:
//   ZALO_APP_ID            app id from developers.zalo.me
//   ZALO_APP_SECRET        app secret key
//   ZALO_OA_REFRESH_TOKEN  initial refresh token (OA granted, zns scope)
// Missing config -> service reports disabled and send() fails soft; callers
// decide whether that is fatal (OTP: yes) or ignorable (marketing ping: no).

const OAUTH_URL = 'https://oauth.zaloapp.com/v4/oa/access_token';
const ZNS_URL = 'https://business.openapi.zalo.me/message/template';
// Refresh 5 minutes before the reported expiry; Zalo access tokens live 1h.
const EXPIRY_SLACK_MS = 5 * 60_000;

export interface ZnsSendResult {
  ok: boolean;
  msgId?: string;
  error?: string;
}

@Injectable()
export class ZnsService {
  private readonly logger = new Logger(ZnsService.name);
  // Serialize refreshes: two concurrent sends must not both spend the
  // single-use refresh token.
  private refreshing: Promise<string | null> | null = null;

  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  get enabled(): boolean {
    return Boolean(
      this.config.get<string>('ZALO_APP_ID') &&
      this.config.get<string>('ZALO_APP_SECRET'),
    );
  }

  // Send one ZNS template message. `phone` accepts 0xxx or 84xxx and is
  // normalized to Zalo's 84xxx form.
  async send(
    phone: string,
    templateId: string,
    templateData: Record<string, string>,
    trackingId?: string,
  ): Promise<ZnsSendResult> {
    if (!this.enabled) return { ok: false, error: 'zns disabled (no config)' };
    if (!templateId) return { ok: false, error: 'missing template id' };
    const token = await this.accessToken();
    if (!token) return { ok: false, error: 'no access token' };

    const body = {
      phone: phone.replace(/^0/, '84'),
      template_id: templateId,
      template_data: templateData,
      tracking_id: trackingId ?? '',
    };
    try {
      const r = await fetch(ZNS_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          access_token: token,
        },
        body: JSON.stringify(body),
      });
      const data = (await r.json()) as {
        error?: number;
        message?: string;
        data?: { msg_id?: string };
      };
      if (data.error && data.error !== 0) {
        this.logger.warn(`ZNS send failed (${data.error}): ${data.message}`);
        return { ok: false, error: `${data.error}: ${data.message}` };
      }
      return { ok: true, msgId: data.data?.msg_id };
    } catch (e) {
      this.logger.warn(`ZNS send error: ${(e as Error).message}`);
      return { ok: false, error: (e as Error).message };
    }
  }

  /* ------------------------- token handling ------------------------- */

  private async accessToken(): Promise<string | null> {
    const row = await this.prisma.zaloOauthToken.findUnique({
      where: { id: 1 },
    });
    if (row && row.expiresAt.getTime() - EXPIRY_SLACK_MS > Date.now()) {
      return row.accessToken;
    }
    // Single-flight: concurrent callers await the same refresh.
    this.refreshing ??= this.refresh(row?.refreshToken).finally(() => {
      this.refreshing = null;
    });
    return this.refreshing;
  }

  private async refresh(storedRefreshToken?: string): Promise<string | null> {
    const appId = this.config.get<string>('ZALO_APP_ID') ?? '';
    const secret = this.config.get<string>('ZALO_APP_SECRET') ?? '';
    const refreshToken =
      storedRefreshToken ??
      this.config.get<string>('ZALO_OA_REFRESH_TOKEN') ??
      '';
    if (!refreshToken) {
      this.logger.error('ZNS: no refresh token (env ZALO_OA_REFRESH_TOKEN)');
      return null;
    }
    try {
      const r = await fetch(OAUTH_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          secret_key: secret,
        },
        body: new URLSearchParams({
          app_id: appId,
          grant_type: 'refresh_token',
          refresh_token: refreshToken,
        }),
      });
      const data = (await r.json()) as {
        access_token?: string;
        refresh_token?: string;
        expires_in?: string;
        error?: number;
        error_description?: string;
      };
      if (!data.access_token || !data.refresh_token) {
        this.logger.error(
          `ZNS token refresh failed: ${data.error ?? ''} ${data.error_description ?? JSON.stringify(data).slice(0, 200)}`,
        );
        return null;
      }
      const expiresAt = new Date(
        Date.now() + (parseInt(data.expires_in ?? '3600', 10) || 3600) * 1000,
      );
      await this.prisma.zaloOauthToken.upsert({
        where: { id: 1 },
        create: {
          id: 1,
          accessToken: data.access_token,
          refreshToken: data.refresh_token,
          expiresAt,
        },
        update: {
          accessToken: data.access_token,
          refreshToken: data.refresh_token,
          expiresAt,
        },
      });
      return data.access_token;
    } catch (e) {
      this.logger.error(`ZNS token refresh error: ${(e as Error).message}`);
      return null;
    }
  }
}
