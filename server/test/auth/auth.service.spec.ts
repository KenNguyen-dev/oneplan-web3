import {
  ConflictException,
  UnauthorizedException,
  UnprocessableEntityException,
  BadRequestException,
} from '@nestjs/common';
import {
  AnalyticsEventName,
  AuthProvider,
  InviteStatus,
  TripStatus,
} from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../src/prisma/prisma.service';
import { AuthService } from '../../src/auth/auth.service';
import { JwtTokenService } from '../../src/auth/jwt.service';
import { AppleAuthService } from '../../src/auth/apple-auth.service';
import { GoogleAuthService } from '../../src/auth/google-auth.service';
import { StorageService } from '../../src/storage/storage.service';

jest.mock('bcrypt');
jest.mock('jose', () => ({
  createRemoteJWKSet: jest.fn(),
  jwtVerify: jest.fn(),
}));
jest.mock('google-auth-library', () => ({
  OAuth2Client: jest.fn().mockImplementation(() => ({
    verifyIdToken: jest.fn(),
  })),
}));

describe('AuthService', () => {
  let service: AuthService;
  let prisma: Record<string, any>;
  let jwtTokenService: Record<string, any>;
  let appleAuthService: Record<string, any>;
  let googleAuthService: Record<string, any>;
  let storageService: Record<string, any>;
  let analyticsMock: { track: jest.Mock };

  const mockUser = {
    id: 1,
    email: 'test@example.com',
    displayName: 'Test User',
    avatarUrl: null,
    createdAt: new Date('2026-03-01T00:00:00.000Z'),
  };

  beforeEach(() => {
    prisma = {
      user: {
        findUnique: jest.fn(),
        findUniqueOrThrow: jest.fn(),
        update: jest.fn(),
      },
      authAccount: {
        findUnique: jest.fn(),
        findFirst: jest.fn(),
        create: jest.fn(),
        count: jest.fn(),
        deleteMany: jest.fn(),
      },
      refreshToken: {
        findUnique: jest.fn(),
        update: jest.fn(),
        updateMany: jest.fn(),
      },
      trip: {
        findMany: jest.fn(),
      },
      $transaction: jest.fn((cb: (tx: any) => Promise<any>) => cb(prisma)),
    };

    jwtTokenService = {
      generateAccessToken: jest.fn().mockReturnValue('access-token'),
      generateRefreshToken: jest
        .fn()
        .mockResolvedValue({ token: 'refresh-token', family: 'family-1' }),
      verifyRefreshToken: jest.fn(),
      getAccessExpiresInSeconds: jest.fn().mockReturnValue(900),
    };

    appleAuthService = {
      verifyIdentityToken: jest.fn(),
    };

    googleAuthService = {
      verifyIdentityToken: jest.fn(),
    };

    storageService = {
      getSignedThumbUrl: jest
        .fn()
        .mockResolvedValue({ url: 'https://signed.example.com/avatar.jpg' }),
    };

    const configService = {
      get: jest.fn((key: string) =>
        key === 'admin.emails' ? ['admin@example.com'] : undefined,
      ),
    };

    analyticsMock = { track: jest.fn() };

    service = new AuthService(
      prisma as unknown as PrismaService,
      jwtTokenService as unknown as JwtTokenService,
      appleAuthService as unknown as AppleAuthService,
      googleAuthService as unknown as GoogleAuthService,
      storageService as unknown as StorageService,
      configService as unknown as import('@nestjs/config').ConfigService,
      analyticsMock as any,
      {
        grantSignupBonus: jest.fn().mockResolvedValue(undefined),
        signupGrantAmount: 2,
      } as any,
    );
  });

  describe('register', () => {
    it('creates a new user and returns auth response', async () => {
      prisma.user.findUnique.mockResolvedValue(null);
      prisma.user.create = jest.fn().mockResolvedValue(mockUser);
      prisma.authAccount.create.mockResolvedValue({});
      (bcrypt.hash as jest.Mock).mockResolvedValue('hashed-password');

      const result = await service.register({
        email: 'Test@Example.com',
        password: 'password123',
        displayName: 'Test User',
      });

      expect(result.accessToken).toBe('access-token');
      expect(result.refreshToken).toBe('refresh-token');
      expect(result.user.email).toBe('test@example.com');
      expect(prisma.user.findUnique).toHaveBeenCalledWith({
        where: { email: 'test@example.com' },
      });
      // Signup-bonus credits are tracked post user-creation tx.
      expect(analyticsMock.track).toHaveBeenCalledWith(
        AnalyticsEventName.SCAN_CREDITS_GRANTED,
        {
          userId: mockUser.id,
          properties: { source: 'signup_bonus', amount: 2 },
        },
      );
    });

    it('throws ConflictException if email already exists', async () => {
      prisma.user.findUnique.mockResolvedValue(mockUser);

      await expect(
        service.register({
          email: 'test@example.com',
          password: 'password123',
          displayName: 'Test User',
        }),
      ).rejects.toThrow(ConflictException);
    });
  });

  describe('login', () => {
    it('returns auth response for valid credentials', async () => {
      prisma.authAccount.findUnique.mockResolvedValue({
        passwordHash: 'hashed-password',
        user: mockUser,
      });
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);

      const result = await service.login({
        email: 'test@example.com',
        password: 'password123',
      });

      expect(result.accessToken).toBe('access-token');
      expect(result.user.id).toBe(1);
    });

    it('throws UnauthorizedException for unknown email', async () => {
      prisma.authAccount.findUnique.mockResolvedValue(null);

      await expect(
        service.login({ email: 'unknown@example.com', password: 'password' }),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('throws UnauthorizedException for wrong password', async () => {
      prisma.authAccount.findUnique.mockResolvedValue({
        passwordHash: 'hashed-password',
        user: mockUser,
      });
      (bcrypt.compare as jest.Mock).mockResolvedValue(false);

      await expect(
        service.login({ email: 'test@example.com', password: 'wrong' }),
      ).rejects.toThrow(UnauthorizedException);
    });
  });

  describe('adminLogin', () => {
    it('returns auth response when email is in ADMIN_EMAILS', async () => {
      prisma.authAccount.findUnique.mockResolvedValue({
        passwordHash: 'hashed-password',
        user: { ...mockUser, email: 'admin@example.com' },
      });
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);

      const result = await service.adminLogin({
        email: 'admin@example.com',
        password: 'password123',
      });

      expect(result.accessToken).toBe('access-token');
      expect(result.user.email).toBe('admin@example.com');
    });

    it('rejects non-admin emails with the same Invalid credentials message', async () => {
      prisma.authAccount.findUnique.mockResolvedValue({
        passwordHash: 'hashed-password',
        user: mockUser, // test@example.com — NOT in admin.emails
      });
      (bcrypt.compare as jest.Mock).mockResolvedValue(true);

      await expect(
        service.adminLogin({
          email: 'test@example.com',
          password: 'password123',
        }),
      ).rejects.toThrow(new UnauthorizedException('Invalid credentials'));
    });

    it('rejects bad password with the same Invalid credentials message', async () => {
      prisma.authAccount.findUnique.mockResolvedValue({
        passwordHash: 'hashed-password',
        user: { ...mockUser, email: 'admin@example.com' },
      });
      (bcrypt.compare as jest.Mock).mockResolvedValue(false);

      await expect(
        service.adminLogin({
          email: 'admin@example.com',
          password: 'wrong',
        }),
      ).rejects.toThrow(new UnauthorizedException('Invalid credentials'));
    });
  });

  describe('socialLogin', () => {
    it('returns tokens for existing social account', async () => {
      googleAuthService.verifyIdentityToken.mockResolvedValue({
        sub: 'google-sub-123',
        email: 'test@example.com',
        emailVerified: true,
      });
      prisma.authAccount.findUnique.mockResolvedValue({
        user: mockUser,
      });

      const result = await service.socialLogin({
        identityToken: 'google-token',
        provider: 'GOOGLE' as any,
      });

      expect(result.accessToken).toBe('access-token');
    });

    it('throws ConflictException when an existing email/password account has the same email (takeover guard)', async () => {
      // Security: auto-link must be blocked when the existing account has an
      // EMAIL provider — an attacker who controls an OAuth identity for the
      // victim's email could otherwise silently take over a password account.
      googleAuthService.verifyIdentityToken.mockResolvedValue({
        sub: 'google-sub-123',
        email: 'test@example.com',
        emailVerified: true,
      });
      prisma.authAccount.findUnique.mockResolvedValue(null); // no existing social account
      prisma.user.findUnique.mockResolvedValue({
        ...mockUser,
        authAccounts: [{ provider: AuthProvider.EMAIL }],
      });

      await expect(
        service.socialLogin({
          identityToken: 'google-token',
          provider: 'GOOGLE' as any,
        }),
      ).rejects.toThrow('An account with this email already exists');
      expect(prisma.authAccount.create).not.toHaveBeenCalled();
    });

    it('creates new user when no match found', async () => {
      googleAuthService.verifyIdentityToken.mockResolvedValue({
        sub: 'google-sub-123',
        email: 'new@example.com',
        emailVerified: true,
      });
      prisma.authAccount.findUnique.mockResolvedValue(null);
      prisma.user.findUnique.mockResolvedValue(null);
      prisma.user.create = jest.fn().mockResolvedValue({
        ...mockUser,
        email: 'new@example.com',
      });
      prisma.authAccount.create.mockResolvedValue({});

      const result = await service.socialLogin({
        identityToken: 'google-token',
        provider: 'GOOGLE' as any,
        displayName: 'New User',
      });

      expect(result.accessToken).toBe('access-token');
    });

    it('throws UnprocessableEntityException when no email available', async () => {
      appleAuthService.verifyIdentityToken.mockResolvedValue({
        sub: 'apple-sub-123',
        email: null,
        emailVerified: false,
      });
      prisma.authAccount.findUnique.mockResolvedValue(null);

      await expect(
        service.socialLogin({
          identityToken: 'apple-token',
          provider: 'APPLE' as any,
        }),
      ).rejects.toThrow(UnprocessableEntityException);
    });

    it('throws ConflictException when emailVerified is false and email is already taken', async () => {
      googleAuthService.verifyIdentityToken.mockResolvedValue({
        sub: 'google-sub-123',
        email: 'test@example.com',
        emailVerified: false,
      });
      prisma.authAccount.findUnique.mockResolvedValue(null);
      prisma.user.findUnique.mockResolvedValue({
        ...mockUser,
        authAccounts: [{ provider: AuthProvider.APPLE }],
      });

      await expect(
        service.socialLogin({
          identityToken: 'google-token',
          provider: 'GOOGLE' as any,
        }),
      ).rejects.toThrow(ConflictException);
    });
  });

  describe('refreshToken', () => {
    it('rotates tokens successfully', async () => {
      jwtTokenService.verifyRefreshToken.mockReturnValue({
        sub: 1,
        type: 'refresh',
        family: 'family-1',
        jti: 'jti-1',
      });
      // Atomic revocation succeeds (count=1 means token was active)
      prisma.refreshToken.updateMany.mockResolvedValue({ count: 1 });
      prisma.refreshToken.findUnique.mockResolvedValue({
        id: 1,
        family: 'family-1',
        expiresAt: new Date(Date.now() + 86400000),
        user: mockUser,
      });

      const result = await service.refreshToken({
        refreshToken: 'old-refresh-token',
      });

      expect(result.accessToken).toBe('access-token');
      expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
        where: { jti: 'jti-1', isRevoked: false },
        data: { isRevoked: true },
      });
    });

    it('revokes entire family on reuse of revoked token', async () => {
      jwtTokenService.verifyRefreshToken.mockReturnValue({
        sub: 1,
        type: 'refresh',
        family: 'family-1',
        jti: 'jti-old',
      });
      // Atomic revocation returns count=0 (token already revoked)
      prisma.refreshToken.updateMany
        .mockResolvedValueOnce({ count: 0 }) // first call: atomic revoke fails
        .mockResolvedValueOnce({}); // second call: revoke entire family

      await expect(
        service.refreshToken({ refreshToken: 'reused-token' }),
      ).rejects.toThrow(UnauthorizedException);

      expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
        where: { family: 'family-1' },
        data: { isRevoked: true },
      });
    });
  });

  describe('unlinkAccount', () => {
    it('removes provider when user has multiple', async () => {
      prisma.authAccount.count.mockResolvedValue(2);
      prisma.authAccount.deleteMany.mockResolvedValue({});
      prisma.user.findUnique.mockResolvedValue({
        ...mockUser,
        authAccounts: [{ provider: AuthProvider.EMAIL }],
        friendCode: 'friend-code',
      });

      const result = await service.unlinkAccount(1, AuthProvider.GOOGLE);

      expect(result.providers).toEqual([AuthProvider.EMAIL]);
    });

    it('throws BadRequestException when only one auth method', async () => {
      prisma.authAccount.count.mockResolvedValue(1);

      await expect(
        service.unlinkAccount(1, AuthProvider.EMAIL),
      ).rejects.toThrow(BadRequestException);
    });
  });

  describe('linkAccount', () => {
    it('throws ConflictException when provider already linked to another user', async () => {
      googleAuthService.verifyIdentityToken.mockResolvedValue({
        sub: 'google-sub-123',
        email: 'other@example.com',
        emailVerified: true,
      });
      prisma.authAccount.findUnique.mockResolvedValue({
        userId: 999, // different user
      });

      await expect(
        service.linkAccount(1, {
          identityToken: 'google-token',
          provider: 'GOOGLE' as any,
        }),
      ).rejects.toThrow(ConflictException);
    });
  });

  describe('getPassportSummary', () => {
    it('returns zero stats and empty distributions when user has no ended trips', async () => {
      prisma.user.findUnique.mockResolvedValue({
        ...mockUser,
        friendCode: 'friend-code',
      });
      prisma.trip.findMany.mockResolvedValue([]);

      const result = await service.getPassportSummary(1);

      expect(prisma.trip.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            status: TripStatus.ENDED,
            members: {
              some: { userId: 1, inviteStatus: InviteStatus.ACCEPTED },
            },
          },
        }),
      );
      expect(result.tripsCount).toBe(0);
      expect(result.countriesCount).toBe(0);
      expect(result.citiesCount).toBe(0);
      expect(result.topCities).toEqual([]);
      expect(result.topCountries).toEqual([]);
    });

    it('aggregates repeated cities and countries from ended trips', async () => {
      prisma.user.findUnique.mockResolvedValue({
        ...mockUser,
        friendCode: 'friend-code',
      });
      prisma.trip.findMany.mockResolvedValue([
        {
          city: { id: 10, name: 'Da Lat' },
          country: { id: 100, name: 'Viet Nam', emoji: '🇻🇳' },
        },
        {
          city: { id: 10, name: 'Da Lat' },
          country: { id: 100, name: 'Viet Nam', emoji: '🇻🇳' },
        },
        {
          city: { id: 11, name: 'Ha Noi' },
          country: { id: 100, name: 'Viet Nam', emoji: '🇻🇳' },
        },
        {
          city: null,
          country: { id: 101, name: 'Thailand', emoji: '🇹🇭' },
        },
      ]);

      const result = await service.getPassportSummary(1);

      expect(result.tripsCount).toBe(4);
      expect(result.citiesCount).toBe(2);
      expect(result.countriesCount).toBe(2);
      expect(result.topCities).toEqual([
        { name: 'Da Lat', count: 2 },
        { name: 'Ha Noi', count: 1 },
      ]);
      expect(result.topCountries).toEqual([
        { name: 'Viet Nam', emoji: '🇻🇳', count: 3 },
        { name: 'Thailand', emoji: '🇹🇭', count: 1 },
      ]);
    });

    it('queries only ended trips for accepted memberships', async () => {
      prisma.user.findUnique.mockResolvedValue({
        ...mockUser,
        friendCode: 'friend-code',
      });
      prisma.trip.findMany.mockResolvedValue([]);

      await service.getPassportSummary(42);

      expect(prisma.trip.findMany).toHaveBeenCalledWith({
        where: {
          status: TripStatus.ENDED,
          members: {
            some: { userId: 42, inviteStatus: InviteStatus.ACCEPTED },
          },
        },
        select: {
          city: { select: { id: true, name: true } },
          country: { select: { id: true, name: true, emoji: true } },
        },
      });
    });
  });

  describe('updateProfile', () => {
    it('updates displayName and returns latest profile', async () => {
      prisma.user.update.mockResolvedValue({
        ...mockUser,
        displayName: 'Updated Name',
      });
      prisma.user.findUnique.mockResolvedValue({
        ...mockUser,
        displayName: 'Updated Name',
        friendCode: 'friend-code',
        authAccounts: [{ provider: AuthProvider.GOOGLE }],
      });

      const result = await service.updateProfile(1, {
        displayName: 'Updated Name',
      });

      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: 1 },
        data: { displayName: 'Updated Name' },
      });
      expect(result.displayName).toBe('Updated Name');
    });

    it('throws BadRequestException for whitespace-only displayName', async () => {
      await expect(
        service.updateProfile(1, { displayName: '   ' }),
      ).rejects.toThrow(BadRequestException);
      expect(prisma.user.update).not.toHaveBeenCalled();
    });
  });
});
