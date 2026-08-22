import { LogicalPushPayload } from './push-payload';

export interface SendResult {
  invalidTokens: string[];
}

export interface PushAdapter {
  readonly provider: 'apns' | 'fcm';
  sendBatch(tokens: string[], payload: LogicalPushPayload): Promise<SendResult>;
}
