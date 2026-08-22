import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as admin from 'firebase-admin';
import { PushAdapter, SendResult } from './push-adapter.interface';
import { LogicalPushPayload } from './push-payload';

const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
  'messaging/sender-id-mismatch',
]);

@Injectable()
export class FcmPushAdapter implements PushAdapter {
  readonly provider = 'fcm' as const;
  private readonly logger = new Logger(FcmPushAdapter.name);
  private readonly messaging: admin.messaging.Messaging | null;

  constructor(config: ConfigService) {
    const serviceAccountPath = config.get<string>('FCM_SERVICE_ACCOUNT_PATH');
    if (!serviceAccountPath) {
      this.messaging = null;
      this.logger.warn('FCM not configured — Android push disabled');
      return;
    }
    try {
      const existing = admin.apps.find((a) => a?.name === 'oneplan-fcm');
      const app =
        existing ??
        admin.initializeApp(
          { credential: admin.credential.cert(serviceAccountPath) },
          'oneplan-fcm',
        );
      this.messaging = admin.messaging(app);
      this.logger.log('FCM provider initialized');
    } catch (err) {
      this.messaging = null;
      this.logger.error(`FCM init failed: ${(err as Error).message}`);
    }
  }

  get isConfigured(): boolean {
    return this.messaging !== null;
  }

  async sendAdminBroadcast(
    tokens: string[],
    input: {
      title: string;
      body: string;
      destination?: string;
      listingId?: number;
    },
  ): Promise<{ sent: number; failed: number; invalidTokens: string[] }> {
    if (!this.messaging || tokens.length === 0) {
      return { sent: 0, failed: 0, invalidTokens: [] };
    }

    // Data-only FCM message: the Android client reads title/body/type from data.
    const data: Record<string, string> = {
      type: 'admin_broadcast',
      title: input.title,
      body: input.body,
    };
    if (input.destination) {
      data.destination = input.destination.toLowerCase();
    }
    if (input.listingId != null) {
      data.listingId = String(input.listingId);
    }

    const message: admin.messaging.MulticastMessage = {
      tokens,
      data,
      android: { priority: 'high', ttl: 24 * 60 * 60 * 1000 },
    };

    let sent = 0;
    let failed = 0;
    const invalidTokens: string[] = [];

    // Chunk to match APNS adapter's pattern for large token tables.
    for (let i = 0; i < tokens.length; i += 500) {
      const batch = tokens.slice(i, i + 500);
      try {
        const response = await this.messaging.sendEachForMulticast({
          ...message,
          tokens: batch,
        });
        response.responses.forEach((res, idx) => {
          if (res.success) {
            sent++;
          } else {
            failed++;
            const code = res.error?.code;
            if (code && INVALID_TOKEN_CODES.has(code)) {
              invalidTokens.push(batch[idx]);
            } else {
              this.logger.warn(
                `FCM admin broadcast failed (token ${idx}): ${code ?? 'unknown'}`,
              );
            }
          }
        });
      } catch (err) {
        this.logger.warn(
          `FCM sendEachForMulticast threw: ${(err as Error).message}`,
        );
        failed += batch.length;
      }
    }

    return { sent, failed, invalidTokens };
  }

  async sendBatch(
    tokens: string[],
    payload: LogicalPushPayload,
  ): Promise<SendResult> {
    if (!this.messaging || tokens.length === 0) {
      return { invalidTokens: [] };
    }

    // Phase 7.4a: reserved routing keys win over user-supplied payload.data.
    // Spreading payload.data FIRST means a buggy/malicious payload.data with
    // {type: "X"} cannot clobber the real routing key downstream.
    const data: Record<string, string> = {
      ...payload.data,
      type: payload.type,
      title: payload.title,
      body: payload.body,
    };
    if (payload.threadId) data.threadId = payload.threadId;

    const message: admin.messaging.MulticastMessage = {
      tokens,
      data,
      android: {
        priority: 'high',
        ttl: 24 * 60 * 60 * 1000,
      },
    };

    try {
      const response = await this.messaging.sendEachForMulticast(message);
      const invalidTokens: string[] = [];
      response.responses.forEach((res, idx) => {
        if (!res.success) {
          const code = res.error?.code;
          if (code && INVALID_TOKEN_CODES.has(code)) {
            invalidTokens.push(tokens[idx]);
          } else {
            this.logger.warn(
              `FCM send failed (token ${idx}): ${code ?? 'unknown'}`,
            );
          }
        }
      });
      return { invalidTokens };
    } catch (err) {
      this.logger.warn(
        `FCM sendEachForMulticast threw: ${(err as Error).message}`,
      );
      return { invalidTokens: [] };
    }
  }
}
