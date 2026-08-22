import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { ApnsPushAdapter } from './apns-push.adapter';
import { PushPayloadBuilder } from './push-payload';

jest.mock('@parse/node-apn');
import apn from '@parse/node-apn';

describe('ApnsPushAdapter', () => {
  let adapter: ApnsPushAdapter;
  let sendMock: jest.Mock;

  beforeEach(async () => {
    sendMock = jest.fn().mockResolvedValue({ failed: [], sent: [] });
    (apn.Provider as unknown as jest.Mock).mockImplementation(() => ({
      send: sendMock,
    }));
    (apn.Notification as unknown as jest.Mock) = jest
      .fn()
      .mockImplementation(() => ({}));

    const moduleRef = await Test.createTestingModule({
      providers: [
        ApnsPushAdapter,
        {
          provide: ConfigService,
          useValue: {
            get: (k: string, d?: string) =>
              ({
                APNS_KEY_ID: 'KID',
                APNS_TEAM_ID: 'TID',
                APNS_KEY_PATH: '/key.p8',
                APNS_BUNDLE_ID: 'com.oneplan.app',
                APNS_PRODUCTION: 'false',
              })[k] ?? d,
          },
        },
      ],
    }).compile();
    adapter = moduleRef.get(ApnsPushAdapter);
  });

  it('no-ops when not configured', async () => {
    const moduleRef = await Test.createTestingModule({
      providers: [
        ApnsPushAdapter,
        { provide: ConfigService, useValue: { get: () => undefined } },
      ],
    }).compile();
    const a = moduleRef.get(ApnsPushAdapter);
    const result = await a.sendBatch(
      ['t1'],
      PushPayloadBuilder.friendRequest({ senderDisplayName: 'A' }),
    );
    expect(result.invalidTokens).toEqual([]);
    expect(sendMock).not.toHaveBeenCalled();
  });

  it('returns 410 tokens as invalid', async () => {
    sendMock.mockResolvedValue({
      failed: [
        { device: 'bad1', status: 410 },
        { device: 'bad2', response: { reason: 'Unregistered' } },
        { device: 'transient', status: 500 },
      ],
    });
    const result = await adapter.sendBatch(
      ['bad1', 'bad2', 'transient', 'good'],
      PushPayloadBuilder.friendRequest({ senderDisplayName: 'A' }),
    );
    expect(result.invalidTokens.sort()).toEqual(['bad1', 'bad2']);
  });

  it('returns BadDeviceToken as invalid', async () => {
    sendMock.mockResolvedValue({
      failed: [{ device: 'bad', response: { reason: 'BadDeviceToken' } }],
    });
    const result = await adapter.sendBatch(
      ['bad'],
      PushPayloadBuilder.friendRequest({ senderDisplayName: 'A' }),
    );
    expect(result.invalidTokens).toEqual(['bad']);
  });

  it('empty token list short-circuits', async () => {
    const result = await adapter.sendBatch(
      [],
      PushPayloadBuilder.friendRequest({ senderDisplayName: 'A' }),
    );
    expect(result.invalidTokens).toEqual([]);
    expect(sendMock).not.toHaveBeenCalled();
  });

  it('catches provider throw and returns empty invalidTokens (phase 7.4a resilience)', async () => {
    sendMock.mockRejectedValue(new Error('connection reset'));
    const result = await adapter.sendBatch(
      ['t1'],
      PushPayloadBuilder.friendRequest({ senderDisplayName: 'A' }),
    );
    expect(result.invalidTokens).toEqual([]);
    expect(sendMock).toHaveBeenCalledTimes(1);
  });
});
