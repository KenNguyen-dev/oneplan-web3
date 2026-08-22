import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { FcmPushAdapter } from './fcm-push.adapter';
import { PushPayloadBuilder } from './push-payload';

const sendEachForMulticastMock = jest.fn();
jest.mock('firebase-admin', () => ({
  apps: [],
  initializeApp: jest.fn(() => ({ name: 'oneplan-fcm' })),
  credential: { cert: jest.fn() },
  messaging: jest.fn(() => ({
    sendEachForMulticast: sendEachForMulticastMock,
  })),
}));

describe('FcmPushAdapter', () => {
  beforeEach(() => {
    sendEachForMulticastMock.mockReset();
  });

  async function makeAdapter(configMap: Record<string, string | undefined>) {
    const moduleRef = await Test.createTestingModule({
      providers: [
        FcmPushAdapter,
        {
          provide: ConfigService,
          useValue: { get: (k: string) => configMap[k] },
        },
      ],
    }).compile();
    return moduleRef.get(FcmPushAdapter);
  }

  it('no-ops when FCM_SERVICE_ACCOUNT_PATH unset', async () => {
    const adapter = await makeAdapter({});
    const result = await adapter.sendBatch(
      ['t1'],
      PushPayloadBuilder.friendRequest({ senderDisplayName: 'A' }),
    );
    expect(result.invalidTokens).toEqual([]);
    expect(sendEachForMulticastMock).not.toHaveBeenCalled();
  });

  it('sends data-only payload (no `notification` field)', async () => {
    sendEachForMulticastMock.mockResolvedValue({
      responses: [{ success: true }],
    });
    const adapter = await makeAdapter({ FCM_SERVICE_ACCOUNT_PATH: '/sa.json' });
    await adapter.sendBatch(
      ['t1'],
      PushPayloadBuilder.chat({
        tripId: 7,
        tripName: 'Da Lat',
        senderName: 'A',
        content: 'hi',
      }),
    );
    const call = sendEachForMulticastMock.mock.calls[0][0];
    expect(call.notification).toBeUndefined();
    expect(call.data.type).toBe('chat');
    expect(call.data.tripId).toBe('7');
    expect(call.data.threadId).toBe('trip-7');
    expect(call.android.priority).toBe('high');
  });

  it('returns UNREGISTERED tokens as invalid', async () => {
    sendEachForMulticastMock.mockResolvedValue({
      responses: [
        {
          success: false,
          error: { code: 'messaging/registration-token-not-registered' },
        },
        { success: true },
        { success: false, error: { code: 'messaging/invalid-argument' } },
        { success: false, error: { code: 'messaging/internal-error' } },
      ],
    });
    const adapter = await makeAdapter({ FCM_SERVICE_ACCOUNT_PATH: '/sa.json' });
    const result = await adapter.sendBatch(
      ['t1', 't2', 't3', 't4'],
      PushPayloadBuilder.friendRequest({ senderDisplayName: 'A' }),
    );
    expect(result.invalidTokens.sort()).toEqual(['t1', 't3']);
  });

  it('empty token list short-circuits', async () => {
    const adapter = await makeAdapter({ FCM_SERVICE_ACCOUNT_PATH: '/sa.json' });
    const result = await adapter.sendBatch(
      [],
      PushPayloadBuilder.friendRequest({ senderDisplayName: 'A' }),
    );
    expect(result.invalidTokens).toEqual([]);
    expect(sendEachForMulticastMock).not.toHaveBeenCalled();
  });

  it('thrown error returns no invalidTokens (transient)', async () => {
    sendEachForMulticastMock.mockRejectedValue(new Error('network down'));
    const adapter = await makeAdapter({ FCM_SERVICE_ACCOUNT_PATH: '/sa.json' });
    const result = await adapter.sendBatch(
      ['t1'],
      PushPayloadBuilder.friendRequest({ senderDisplayName: 'A' }),
    );
    expect(result.invalidTokens).toEqual([]);
  });

  it('engagement push carries its specific subtype in data.type over FCM (regression: was clobbered to generic "engagement")', async () => {
    sendEachForMulticastMock.mockResolvedValue({
      responses: [{ success: true }],
    });
    const adapter = await makeAdapter({ FCM_SERVICE_ACCOUNT_PATH: '/sa.json' });
    await adapter.sendBatch(
      ['t1'],
      PushPayloadBuilder.engagement({
        title: 'Your next trip awaits',
        body: 'Come back!',
        deepLink: { type: 'engagement_dormant' },
      }),
    );
    const sent = sendEachForMulticastMock.mock.calls[0][0];
    expect(sent.data.type).toBe('engagement_dormant');
  });

  it('reserved routing keys win over payload.data (phase 7.4a precedence fix)', async () => {
    sendEachForMulticastMock.mockResolvedValue({
      responses: [{ success: true }],
    });
    const adapter = await makeAdapter({ FCM_SERVICE_ACCOUNT_PATH: '/sa.json' });
    await adapter.sendBatch(['t1'], {
      type: 'chat',
      title: 'Real title',
      body: 'Real body',
      data: {
        type: 'MALICIOUS',
        title: 'Spoofed',
        body: 'Spoofed body',
        tripId: '42',
      },
    });
    const sent = sendEachForMulticastMock.mock.calls[0][0];
    expect(sent.data.type).toBe('chat');
    expect(sent.data.title).toBe('Real title');
    expect(sent.data.body).toBe('Real body');
    expect(sent.data.tripId).toBe('42');
  });
});
