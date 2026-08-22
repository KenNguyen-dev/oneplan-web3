import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { JwtPayload } from './decorators/current-user.decorator';

export interface JwtRefreshPayload {
  sub: number;
  type: 'refresh';
  family: string;
  jti: string;
}

@Injectable()
export class JwtTokenService {
  private readonly refreshSecret: string;
  private readonly refreshExpiration: string;

  constructor(
    private readonly jwtService: JwtService,
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    this.refreshSecret = this.config.getOrThrow<string>('JWT_REFRESH_SECRET');
    this.refreshExpiration = this.config.get<string>(
      'JWT_REFRESH_EXPIRATION',
      '30d',
    );
  }

  generateAccessToken(userId: number, email: string): string {
    const payload: Omit<JwtPayload, 'iat' | 'exp'> = {
      sub: userId,
      email,
      type: 'access',
    };
    return this.jwtService.sign(payload);
  }

  async generateRefreshToken(
    userId: number,
    family?: string,
  ): Promise<{ token: string; family: string }> {
    const tokenFamily = family ?? randomUUID();
    const jti = randomUUID();

    const payload: Omit<JwtRefreshPayload, 'iat' | 'exp'> = {
      sub: userId,
      type: 'refresh',
      family: tokenFamily,
      jti,
    };

    const token = this.jwtService.sign(payload as Record<string, unknown>, {
      secret: this.refreshSecret,
      expiresIn: this.refreshExpiration as any,
      algorithm: 'HS256',
    });

    const expiresAt = new Date(
      Date.now() + this.parseExpirationSeconds() * 1000,
    );

    await this.prisma.refreshToken.create({
      data: {
        userId,
        jti,
        family: tokenFamily,
        expiresAt,
      },
    });

    return { token, family: tokenFamily };
  }

  verifyAccessToken(token: string): JwtPayload {
    const payload = this.jwtService.verify<JwtPayload>(token);
    if (payload.type !== 'access') {
      throw new Error('Invalid token type');
    }
    return payload;
  }

  verifyRefreshToken(token: string): JwtRefreshPayload {
    const payload = this.jwtService.verify<JwtRefreshPayload>(token, {
      secret: this.refreshSecret,
      algorithms: ['HS256'],
    });
    if (payload.type !== 'refresh') {
      throw new Error('Invalid token type');
    }
    return payload;
  }

  getAccessExpiresInSeconds(): number {
    const expiration = this.config.get<string>('JWT_ACCESS_EXPIRATION', '15m');
    const match = expiration.match(/^(\d+)([smhd])$/);
    if (!match) return 900; // default 15m
    const value = parseInt(match[1], 10);
    const unit = match[2];
    switch (unit) {
      case 's':
        return value;
      case 'm':
        return value * 60;
      case 'h':
        return value * 3600;
      case 'd':
        return value * 86400;
      default:
        return 900;
    }
  }

  private parseExpirationSeconds(): number {
    const match = this.refreshExpiration.match(/^(\d+)([smhd])$/);
    if (!match) return 30 * 86400; // default 30 days
    const value = parseInt(match[1], 10);
    switch (match[2]) {
      case 's':
        return value;
      case 'm':
        return value * 60;
      case 'h':
        return value * 3600;
      case 'd':
        return value * 86400;
      default:
        return 30 * 86400;
    }
  }
}
