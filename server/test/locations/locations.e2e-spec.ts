import { ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import { AppModule } from '../../src/app.module';
import { PrismaService } from '../../src/prisma/prisma.service';

describe('Locations (e2e)', () => {
  let app: NestFastifyApplication;
  let prismaMock: Record<string, any>;

  const mockCountries = [
    {
      id: 1,
      name: 'Australia',
      iso2: 'AU',
      iso3: 'AUS',
      phoneCode: '61',
      capital: 'Canberra',
      currency: 'AUD',
      region: 'Oceania',
      subRegion: 'Australia and New Zealand',
      emoji: '🇦🇺',
    },
    {
      id: 2,
      name: 'Brazil',
      iso2: 'BR',
      iso3: 'BRA',
      phoneCode: '55',
      capital: 'Brasilia',
      currency: 'BRL',
      region: 'Americas',
      subRegion: 'South America',
      emoji: '🇧🇷',
    },
  ];

  const mockStates = [
    {
      id: 1,
      name: 'California',
      iso2: 'CA',
      type: 'state',
      latitude: 36.778261,
      longitude: -119.417932,
    },
    {
      id: 2,
      name: 'Texas',
      iso2: 'TX',
      type: 'state',
      latitude: 31.968599,
      longitude: -99.90181,
    },
  ];

  const mockCities = [
    {
      id: 10,
      name: 'Los Angeles',
      latitude: 34.052234,
      longitude: -118.243685,
    },
    {
      id: 11,
      name: 'San Francisco',
      latitude: 37.774929,
      longitude: -122.419416,
    },
  ];

  beforeEach(async () => {
    prismaMock = {
      $queryRawUnsafe: jest.fn().mockResolvedValue([{ '?column?': 1 }]),
      $disconnect: jest.fn(),
      country: { findMany: jest.fn().mockResolvedValue(mockCountries) },
      state: { findMany: jest.fn().mockResolvedValue(mockStates) },
      city: { findMany: jest.fn().mockResolvedValue(mockCities) },
    };

    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(PrismaService)
      .useValue(prismaMock)
      .compile();

    app = moduleFixture.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter(),
    );
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, transform: true }),
    );
    await app.init();
    await app.getHttpAdapter().getInstance().ready();
  });

  afterEach(async () => {
    await app.close();
  });

  describe('GET /countries', () => {
    it('returns list of countries', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/countries',
      });

      expect(response.statusCode).toBe(200);
      expect(response.json()).toEqual(mockCountries);
      expect(prismaMock.country.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ orderBy: { name: 'asc' } }),
      );
    });
  });

  describe('GET /countries/:id/states', () => {
    it('returns states for a country', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/countries/233/states',
      });

      expect(response.statusCode).toBe(200);
      expect(response.json()).toEqual(mockStates);
      expect(prismaMock.state.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { countryId: 233 } }),
      );
    });

    it('returns 400 for non-numeric id', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/countries/abc/states',
      });

      expect(response.statusCode).toBe(400);
    });
  });

  describe('GET /states/:id/cities', () => {
    it('returns paginated cities', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/states/1416/cities',
      });

      expect(response.statusCode).toBe(200);
      const body = response.json();
      expect(body.data).toEqual(mockCities);
      expect(body.nextCursor).toBeNull();
    });

    it('passes search query to service', async () => {
      await app.inject({
        method: 'GET',
        url: '/states/1416/cities?search=Los',
      });

      expect(prismaMock.city.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            name: { startsWith: 'Los', mode: 'insensitive' },
          }),
        }),
      );
    });

    it('returns 400 for take exceeding max', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/states/1416/cities?take=999',
      });

      expect(response.statusCode).toBe(400);
    });

    it('returns 400 for non-numeric take', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/states/1416/cities?take=abc',
      });

      expect(response.statusCode).toBe(400);
    });

    it('returns 400 for non-numeric cursor', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/states/1416/cities?cursor=abc',
      });

      expect(response.statusCode).toBe(400);
    });

    it('returns 400 for non-numeric state id', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/states/abc/cities',
      });

      expect(response.statusCode).toBe(400);
    });
  });
});
