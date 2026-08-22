import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import apn from '@parse/node-apn';
import { PushAdapter, SendResult } from './push-adapter.interface';
import { LogicalPushPayload } from './push-payload';

@Injectable()
export class ApnsPushAdapter implements PushAdapter {
  readonly provider = 'apns' as const;
  private readonly logger = new Logger(ApnsPushAdapter.name);
  private readonly apnProvider: apn.Provider | null;
  private readonly bundleId: string;

  constructor(config: ConfigService) {
    const keyId = config.get<string>('APNS_KEY_ID');
    const teamId = config.get<string>('APNS_TEAM_ID');
    const keyPath = config.get<string>('APNS_KEY_PATH');
    this.bundleId = config.get<string>('APNS_BUNDLE_ID', 'com.oneplan.app');

    if (keyId && teamId && keyPath) {
      this.apnProvider = new apn.Provider({
        token: { key: keyPath, keyId, teamId },
        production: config.get<string>('APNS_PRODUCTION') === 'true',
      });
      this.logger.log('APNs provider initialized');
    } else {
      this.apnProvider = null;
      this.logger.warn('APNs not configured — iOS push disabled');
    }
  }

  get isConfigured(): boolean {
    return this.apnProvider !== null;
  }

  // Admin-composed broadcast / targeted push. Distinct from sendBatch's typed
  // logical payloads: admin pushes carry a free-form title/body and an
  // 'admin_broadcast' type that routes the tap on iOS. Returns send/fail counts
  // (sendBatch only surfaces invalid tokens).
  async sendAdminBroadcast(
    tokens: string[],
    input: {
      title: string;
      body: string;
      destination?: string;
      listingId?: number;
    },
  ): Promise<{ sent: number; failed: number; invalidTokens: string[] }> {
    if (!this.apnProvider || tokens.length === 0) {
      return { sent: 0, failed: 0, invalidTokens: [] };
    }

    const notification = new apn.Notification();
    notification.alert = { title: input.title, body: input.body };
    notification.sound = 'default';
    notification.topic = this.bundleId;
    notification.payload = {
      type: 'admin_broadcast',
      ...(input.destination
        ? { destination: input.destination.toLowerCase() }
        : {}),
      ...(input.listingId != null
        ? { listingId: String(input.listingId) }
        : {}),
    };

    let sent = 0;
    let failed = 0;
    const invalidTokens: string[] = [];

    // Chunk so a large device_token table isn't loaded into one unbounded send.
    for (let i = 0; i < tokens.length; i += 1000) {
      const batch = tokens.slice(i, i + 1000);
      const result = await this.apnProvider.send(notification, batch);
      sent += result.sent.length;
      failed += result.failed.length;
      invalidTokens.push(
        ...result.failed
          .filter(
            (f) =>
              f.status === 410 ||
              f.response?.reason === 'BadDeviceToken' ||
              f.response?.reason === 'Unregistered',
          )
          .map((f) => f.device),
      );
    }

    return { sent, failed, invalidTokens };
  }

  async sendBatch(
    tokens: string[],
    payload: LogicalPushPayload,
  ): Promise<SendResult> {
    if (!this.apnProvider || tokens.length === 0) {
      return { invalidTokens: [] };
    }

    const notification = new apn.Notification();
    notification.alert =
      payload.type === 'chat'
        ? {
            title: payload.title,
            subtitle: payload.data.senderName,
            body: payload.body,
          }
        : { title: payload.title, body: payload.body };
    notification.sound = 'default';
    if (payload.badge !== undefined) notification.badge = payload.badge;
    if (payload.threadId) notification.threadId = payload.threadId;
    if (payload.priority !== undefined)
      notification.priority = payload.priority;
    notification.topic = this.bundleId;
    notification.payload = this.buildApnsPayload(payload);

    try {
      const result = await this.apnProvider.send(notification, tokens);
      const invalidTokens = result.failed
        .filter(
          (f) =>
            f.status === 410 ||
            f.response?.reason === 'BadDeviceToken' ||
            f.response?.reason === 'Unregistered',
        )
        .map((f) => f.device);
      return { invalidTokens };
    } catch (err) {
      this.logger.warn(`APNs provider threw: ${(err as Error).message}`);
      return { invalidTokens: [] };
    }
  }

  private buildApnsPayload(
    payload: LogicalPushPayload,
  ): Record<string, unknown> {
    const out: Record<string, unknown> = { type: payload.type };
    for (const [k, v] of Object.entries(payload.data)) {
      // APNs preserves numeric tripId/planItemId for iOS NotificationPayloadParser
      if (k === 'tripId' || k === 'planItemId') {
        const n = Number(v);
        if (Number.isFinite(n)) {
          out[k] = n;
          continue;
        }
      }
      out[k] = v;
    }
    return out;
  }
}
