import { ConfigService } from '@nestjs/config';
import { Currency, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ExchangeRatesService } from './exchange-rates.service';

describe('ExchangeRatesService', () => {
  let service: ExchangeRatesService;
  let prisma: any;
  let config: Pick<ConfigService, 'get'>;
  let fetchSpy: jest.SpyInstance;

  const API_KEY = 'test-api-key';

  const buildService = (apiKey: string = API_KEY) => {
    prisma = {
      exchangeRate: {
        findUnique: jest.fn(),
        upsert: jest.fn(),
      },
      $transaction: jest.fn(async (ops: Promise<unknown>[]) =>
        Promise.all(ops),
      ),
    };
    config = {
      get: jest.fn((key: string) =>
        key === 'EXCHANGERATE_API_KEY' ? apiKey : undefined,
      ) as any,
    };
    service = new ExchangeRatesService(
      prisma as PrismaService,
      config as ConfigService,
    );
  };

  beforeEach(() => {
    fetchSpy = jest.spyOn(globalThis, 'fetch').mockImplementation(() => {
      throw new Error(
        'unexpected fetch call — test should have mocked this explicitly',
      );
    });
    buildService();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const mockFetchSuccess = (
    conversionRates: Record<string, number>,
    baseCode: string = 'USD',
  ) => {
    fetchSpy.mockReset();
    fetchSpy.mockImplementation(
      async () =>
        ({
          ok: true,
          status: 200,
          json: async () => ({
            result: 'success',
            base_code: baseCode,
            conversion_rates: conversionRates,
          }),
        }) as unknown as Response,
    );
  };

  const mockFetchApiError = () => {
    fetchSpy.mockReset();
    fetchSpy.mockImplementation(
      async () =>
        ({
          ok: true,
          status: 200,
          json: async () => ({
            result: 'error',
            'error-type': 'invalid-key',
          }),
        }) as unknown as Response,
    );
  };

  const mockFetchNetworkError = () => {
    fetchSpy.mockReset();
    fetchSpy.mockImplementation(async () => {
      throw new Error('network down');
    });
  };

  const makeRateRow = (
    from: Currency,
    to: Currency,
    rate: string,
    fetchedAt: Date,
  ) => ({
    id: 1,
    fromCurrency: from,
    toCurrency: to,
    rate: new Prisma.Decimal(rate),
    fetchedAt,
    source: 'exchangerate-api.com',
  });

  describe('getRate', () => {
    it('returns 1 when from === to without any IO', async () => {
      const result = await service.getRate(Currency.USD, Currency.USD);
      expect(result.rate.toString()).toBe('1');
      expect(result.isStale).toBe(false);
      expect(fetchSpy).not.toHaveBeenCalled();
      expect(prisma.exchangeRate.findUnique).not.toHaveBeenCalled();
    });

    it('returns fresh in-memory cache hit without DB or fetch', async () => {
      // Seed in-memory cache via a successful fetch.
      prisma.exchangeRate.findUnique.mockResolvedValue(null);
      mockFetchSuccess({
        USD: 1,
        VND: 24500,
        EUR: 0.92,
        THB: 36.5,
        KRW: 1360,
        JPY: 152,
        CNY: 7.2,
        TWD: 32.1,
        SGD: 1.35,
        MYR: 4.7,
      });
      prisma.exchangeRate.upsert.mockImplementation((args: any) =>
        Promise.resolve({
          id: 1,
          ...args.create,
          source: 'exchangerate-api.com',
        }),
      );
      const first = await service.getRate(Currency.USD, Currency.VND);
      expect(first.rate.toString()).toBe('24500');

      // Reset mocks to ensure no further IO happens.
      prisma.exchangeRate.findUnique.mockClear();
      fetchSpy.mockClear();

      const second = await service.getRate(Currency.USD, Currency.VND);
      expect(second.rate.toString()).toBe('24500');
      expect(second.isStale).toBe(false);
      expect(prisma.exchangeRate.findUnique).not.toHaveBeenCalled();
      expect(fetchSpy).not.toHaveBeenCalled();
    });

    it('returns fresh DB cache hit and promotes to memory (no fetch)', async () => {
      const fetchedAt = new Date(); // fresh
      prisma.exchangeRate.findUnique.mockResolvedValue(
        makeRateRow(Currency.USD, Currency.VND, '24500', fetchedAt),
      );

      const result = await service.getRate(Currency.USD, Currency.VND);
      expect(result.rate.toString()).toBe('24500');
      expect(result.isStale).toBe(false);
      expect(fetchSpy).not.toHaveBeenCalled();

      // Second call hits memory (DB call count unchanged).
      const callCountAfterFirst =
        prisma.exchangeRate.findUnique.mock.calls.length;
      const second = await service.getRate(Currency.USD, Currency.VND);
      expect(second.rate.toString()).toBe('24500');
      expect(prisma.exchangeRate.findUnique.mock.calls.length).toBe(
        callCountAfterFirst,
      );
    });

    it('fetches live, upserts all 9 pairs, and returns fresh rate on cache miss', async () => {
      prisma.exchangeRate.findUnique.mockResolvedValue(null);
      const rates = {
        USD: 1,
        VND: 24500,
        EUR: 0.92,
        THB: 36.5,
        KRW: 1360,
        JPY: 152,
        CNY: 7.2,
        TWD: 32.1,
        SGD: 1.35,
        MYR: 4.7,
      };
      mockFetchSuccess(rates);
      prisma.exchangeRate.upsert.mockImplementation((args: any) =>
        Promise.resolve({
          id: 1,
          ...args.create,
          source: 'exchangerate-api.com',
        }),
      );

      const result = await service.getRate(Currency.USD, Currency.VND);
      expect(result.rate.toString()).toBe('24500');
      expect(result.isStale).toBe(false);
      expect(fetchSpy).toHaveBeenCalledTimes(1);
      expect(fetchSpy.mock.calls[0][0]).toContain(`/v6/${API_KEY}/latest/USD`);
      // All 9 non-self pairs upserted in a single transaction.
      expect(prisma.exchangeRate.upsert).toHaveBeenCalledTimes(9);
      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    });

    it('falls back to stale DB row when API returns result:error', async () => {
      const stale = new Date(Date.now() - 48 * 60 * 60 * 1000); // 48h old
      prisma.exchangeRate.findUnique.mockResolvedValue(
        makeRateRow(Currency.USD, Currency.VND, '23000', stale),
      );
      mockFetchApiError();

      const result = await service.getRate(Currency.USD, Currency.VND);
      expect(result.rate.toString()).toBe('23000');
      expect(result.isStale).toBe(true);
      expect(prisma.exchangeRate.upsert).not.toHaveBeenCalled();
    });

    it('returns static fallback with isStale when fetch throws and no DB row exists', async () => {
      prisma.exchangeRate.findUnique.mockResolvedValue(null);
      mockFetchNetworkError();

      const result = await service.getRate(Currency.USD, Currency.VND);
      // Static USD→VND bootstrap rate is 24500.
      expect(result.rate.toString()).toBe('24500');
      expect(result.isStale).toBe(true);
      expect(prisma.exchangeRate.upsert).not.toHaveBeenCalled();
    });

    it('skips fetch entirely when API key is empty and uses static fallback', async () => {
      buildService('');
      prisma.exchangeRate.findUnique.mockResolvedValue(null);

      const result = await service.getRate(Currency.USD, Currency.THB);
      expect(result.isStale).toBe(true);
      // 36.5 is the static USD→THB rate.
      expect(Number(result.rate.toString())).toBeCloseTo(36.5, 4);
      expect(fetchSpy).not.toHaveBeenCalled();
    });

    it('dedupes concurrent fetches for the same base currency', async () => {
      prisma.exchangeRate.findUnique.mockResolvedValue(null);

      // Controlled fetch: returns a promise that only resolves when we
      // explicitly call `resolveFetch`. This lets the test observe the
      // inflight state before any fetch settles.
      let resolveFetch: (value: unknown) => void = () => {};
      const fetchGate = new Promise((resolve) => {
        resolveFetch = resolve;
      });
      fetchSpy.mockReset();
      fetchSpy.mockImplementation(() => fetchGate);

      prisma.exchangeRate.upsert.mockImplementation((args: any) =>
        Promise.resolve({
          id: 1,
          ...args.create,
          source: 'exchangerate-api.com',
        }),
      );

      // Fire three concurrent callers — two for the same base currency
      // (to verify basic dedup) and one more to exercise the "joiner"
      // code path that the identity-guarded delete protects.
      const p1 = service.getRate(Currency.USD, Currency.VND);
      const p2 = service.getRate(Currency.USD, Currency.EUR);
      const p3 = service.getRate(Currency.USD, Currency.THB);

      // Wait until the first caller has actually triggered the live fetch
      // (i.e. cleared DB miss, entered runInflight, and invoked fetch).
      // Poll with `setImmediate` so we're not coupled to the internal
      // microtask count of getRate. Bail after a generous ceiling to
      // prevent infinite hangs if dedup is fully broken.
      const deadline = Date.now() + 1_000;
      while (fetchSpy.mock.calls.length === 0 && Date.now() < deadline) {
        await new Promise((r) => setImmediate(r));
      }
      // Drain several additional ticks to let any non-deduped parallel
      // fetch calls land — if dedup is broken, more callers will reach
      // fetch now, and the count will exceed 1.
      for (let i = 0; i < 10; i++) {
        await new Promise((r) => setImmediate(r));
      }
      expect(fetchSpy).toHaveBeenCalledTimes(1);

      // At this moment the fetch is still pending. If dedup were broken,
      // the other callers would have already invoked fetch a second/third
      // time — the assertion above would have caught it. Now release the
      // fetch and let all callers resume.
      resolveFetch({
        ok: true,
        status: 200,
        json: async () => ({
          result: 'success',
          base_code: 'USD',
          conversion_rates: {
            USD: 1,
            VND: 24500,
            EUR: 0.92,
            THB: 36.5,
            KRW: 1360,
            JPY: 152,
            CNY: 7.2,
            TWD: 32.1,
            SGD: 1.35,
            MYR: 4.7,
          },
        }),
      });

      const [r1, r2, r3] = await Promise.all([p1, p2, p3]);
      expect(r1.rate.toString()).toBe('24500');
      expect(r2.rate.toString()).toBe('0.92');
      expect(r3.rate.toString()).toBe('36.5');

      // Exactly one live fetch despite three concurrent callers.
      expect(fetchSpy).toHaveBeenCalledTimes(1);
    });
  });
});
