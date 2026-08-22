import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class HealthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {}

  live() {
    return {
      status: 'ok',
      commitHash: this.serverCommitHash(),
    };
  }

  async ready() {
    try {
      await this.prisma.$queryRawUnsafe('SELECT 1');
      return { status: 'ok', database: 'up' };
    } catch {
      throw new ServiceUnavailableException({
        status: 'error',
        database: 'down',
      });
    }
  }

  private serverCommitHash(): string | null {
    const candidates = [
      this.configService.get<string>('SERVER_COMMIT_SHA'),
      this.configService.get<string>('GIT_COMMIT_SHA'),
      this.configService.get<string>('COMMIT_SHA'),
    ];

    const commitHash = candidates
      .map((value) => value?.trim())
      .find((value) => value && value.length > 0);

    return commitHash ?? null;
  }
}
