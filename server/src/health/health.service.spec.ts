import { ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { HealthService } from './health.service';

describe('HealthService', () => {
  let service: HealthService;
  let prisma: Pick<PrismaService, '$queryRawUnsafe'>;
  let config: Pick<ConfigService, 'get'>;

  beforeEach(() => {
    prisma = {
      $queryRawUnsafe: jest.fn(),
    };
    config = {
      get: jest.fn(),
    };

    service = new HealthService(
      prisma as PrismaService,
      config as ConfigService,
    );
  });

  it('returns live status with null commit hash by default', () => {
    expect(service.live()).toEqual({ status: 'ok', commitHash: null });
  });

  it('returns server commit hash from config', () => {
    (config.get as jest.Mock).mockImplementation((key: string) =>
      key === 'SERVER_COMMIT_SHA' ? 'abc1234def5678' : undefined,
    );

    expect(service.live()).toEqual({
      status: 'ok',
      commitHash: 'abc1234def5678',
    });
  });

  it('returns ready status when database is up', async () => {
    (prisma.$queryRawUnsafe as jest.Mock).mockResolvedValue([
      { '?column?': 1 },
    ]);

    await expect(service.ready()).resolves.toEqual({
      status: 'ok',
      database: 'up',
    });
  });

  it('throws service unavailable when database is down', async () => {
    (prisma.$queryRawUnsafe as jest.Mock).mockRejectedValue(
      new Error('connection failed'),
    );

    await expect(service.ready()).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
});
