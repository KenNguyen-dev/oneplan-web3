import {
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GooglePlayPurchaseClient } from '../google-play/google-play-purchase-client';
import { MarketplacePurchaseVerifierService } from './marketplace-purchase-verifier.service';

jest.mock('google-auth-library', () => ({
  GoogleAuth: jest.fn().mockImplementation(() => ({
    getClient: jest.fn().mockResolvedValue({
      getAccessToken: jest.fn().mockResolvedValue({ token: 'access-token' }),
    }),
  })),
}));

describe('MarketplacePurchaseVerifierService', () => {
  let service: MarketplacePurchaseVerifierService;
  const fetchMock = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    global.fetch = fetchMock as unknown as typeof fetch;

    const config = {
      get: jest.fn((key: string) => {
        const map: Record<string, string> = {
          GOOGLE_PLAY_PACKAGE_NAME: 'com.oneplan.app',
          GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL: 'svc@oneplan.iam',
          GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY: 'pk\\nline',
        };
        return map[key];
      }),
    };
    const play = new GooglePlayPurchaseClient(
      config as unknown as ConfigService,
    );
    service = new MarketplacePurchaseVerifierService(play);
  });

  const listing = { id: 7, playProductId: 'marketplace.dalat.3d2n' };
  const dto = {
    packageName: 'com.oneplan.app',
    productId: 'marketplace.dalat.3d2n',
    purchaseToken: 'tok-1',
    orderId: 'GPA.1',
    purchaseTimeMillis: undefined,
    purchaseState: 0,
  };

  it('rejects a listing not configured for Google Play', async () => {
    await expect(
      service.verifyGooglePlayPurchase({ id: 1, playProductId: null }, dto),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('rejects a product/listing mismatch before any network call', async () => {
    await expect(
      service.verifyGooglePlayPurchase(listing, {
        ...dto,
        productId: 'marketplace.other',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('rejects a package mismatch before any network call', async () => {
    await expect(
      service.verifyGooglePlayPurchase(listing, {
        ...dto,
        packageName: 'com.evil.app',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('verifies a purchase and acknowledges when not yet acknowledged', async () => {
    fetchMock
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          orderId: 'GPA.99',
          purchaseState: 0,
          purchaseTimeMillis: '1700000000000',
          acknowledgementState: 0,
        }),
      })
      .mockResolvedValueOnce({ ok: true, status: 200 });

    const result = await service.verifyGooglePlayPurchase(listing, dto);

    expect(result.orderId).toBe('GPA.99');
    expect(result.purchaseTime).toEqual(new Date(1700000000000));
    // get + acknowledge
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[1][0]).toContain(':acknowledge');
    expect(fetchMock.mock.calls[1][1].method).toBe('POST');
  });

  it('does not re-acknowledge an already-acknowledged purchase', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        orderId: 'GPA.99',
        purchaseState: 0,
        acknowledgementState: 1,
      }),
    });

    await service.verifyGooglePlayPurchase(listing, dto);

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('treats a 400 on acknowledge ("already acknowledged") as success', async () => {
    fetchMock
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ purchaseState: 0, acknowledgementState: 0 }),
      })
      .mockResolvedValueOnce({ ok: false, status: 400 });

    const result = await service.verifyGooglePlayPurchase(listing, dto);

    expect(result.productId).toBe(dto.productId);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('fails closed when acknowledgement cannot be confirmed', async () => {
    fetchMock
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ purchaseState: 0, acknowledgementState: 0 }),
      })
      .mockResolvedValueOnce({ ok: false, status: 500 });

    await expect(
      service.verifyGooglePlayPurchase(listing, dto),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('rejects an uncompleted purchase (cancelled/pending) without acknowledging', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ purchaseState: 1 }),
    });

    await expect(
      service.verifyGooglePlayPurchase(listing, dto),
    ).rejects.toBeInstanceOf(BadRequestException);
    // only the GET, no acknowledge
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('throws when the purchase token is not found (404)', async () => {
    fetchMock.mockResolvedValueOnce({ ok: false, status: 404 });

    await expect(
      service.verifyGooglePlayPurchase(listing, dto),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
