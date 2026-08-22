import { BadRequestException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../src/prisma/prisma.service';
import { TripActivityService } from '../../src/trip-activity/trip-activity.service';
import { StorageService } from '../../src/storage/storage.service';
import { UploadTarget } from '../../src/storage/constants/upload-targets';

// Mock @google-cloud/storage. The Storage constructor returns a stub whose
// bucket(name).file(key) yields a file stub with the methods StorageService
// calls. Each file() call returns a shared object so tests can assert on
// invocation counts without having to track every (bucket, key) tuple.
const fileStub = {
  getSignedUrl: jest
    .fn()
    .mockResolvedValue(['https://storage.example.com/signed-url']),
  exists: jest.fn().mockResolvedValue([true]),
  download: jest.fn().mockResolvedValue([Buffer.from('img')]),
  save: jest.fn().mockResolvedValue(undefined),
  delete: jest.fn().mockResolvedValue(undefined),
};

const bucketStub = {
  file: jest.fn(() => fileStub),
};

jest.mock('@google-cloud/storage', () => ({
  Storage: jest.fn().mockImplementation(() => ({
    bucket: jest.fn(() => bucketStub),
  })),
}));

// sharp is invoked inside generateThumbnail. Stub the chain so it returns a
// buffer without spinning up libvips during unit tests.
jest.mock('sharp', () => {
  const chain = {
    rotate: jest.fn(() => chain),
    resize: jest.fn(() => chain),
    webp: jest.fn(() => chain),
    toBuffer: jest.fn().mockResolvedValue(Buffer.from('thumb')),
  };
  return jest.fn(() => chain);
});

describe('StorageService', () => {
  let service: StorageService;
  let prisma: Record<string, any>;
  let config: Record<string, any>;
  let activityService: Record<string, any>;

  beforeEach(() => {
    jest.clearAllMocks();
    fileStub.getSignedUrl.mockResolvedValue([
      'https://storage.example.com/signed-url',
    ]);
    fileStub.exists.mockResolvedValue([true]);
    fileStub.download.mockResolvedValue([Buffer.from('img')]);
    fileStub.save.mockResolvedValue(undefined);
    fileStub.delete.mockResolvedValue(undefined);

    prisma = {
      user: {
        findUniqueOrThrow: jest.fn().mockResolvedValue({ id: 1 }),
        findUnique: jest.fn().mockResolvedValue(null),
        update: jest.fn().mockResolvedValue({}),
      },
      trip: {
        findUniqueOrThrow: jest.fn().mockResolvedValue({ id: 1 }),
        findUnique: jest.fn().mockResolvedValue(null),
        update: jest.fn().mockResolvedValue({}),
      },
      marketplaceListing: {
        findUniqueOrThrow: jest.fn().mockResolvedValue({ id: 1 }),
      },
      board: {
        findUniqueOrThrow: jest.fn().mockResolvedValue({ id: 1 }),
        findUnique: jest.fn().mockResolvedValue(null),
        update: jest.fn().mockResolvedValue({}),
      },
      expense: {
        findUniqueOrThrow: jest.fn().mockResolvedValue({ id: 1 }),
        findUnique: jest.fn().mockResolvedValue(null),
        update: jest.fn().mockResolvedValue({}),
      },
      tripPhoto: {
        create: jest.fn().mockResolvedValue({ id: 1 }),
      },
    };

    config = {
      getOrThrow: jest.fn((key: string) => {
        const values: Record<string, string> = {
          GCS_MEDIA_BUCKET: 'oneplan-media',
        };
        const v = values[key];
        if (v === undefined) throw new Error(`unexpected getOrThrow: ${key}`);
        return v;
      }),
      get: jest.fn((key: string) => {
        const values: Record<string, string> = {
          GOOGLE_CLOUD_PROJECT: 'test-project',
          STORAGE_SA_KEY_FILE: '/tmp/storage-sa.json',
        };
        return values[key];
      }),
    };

    activityService = { log: jest.fn() };

    service = new StorageService(
      config as unknown as ConfigService,
      prisma as unknown as PrismaService,
      activityService as unknown as TripActivityService,
      { track: jest.fn() } as any,
    );
    service.onModuleInit();
  });

  describe('createPresignedUpload', () => {
    it('returns a presigned URL for a valid request', async () => {
      const result = await service.createPresignedUpload({
        target: UploadTarget.USER_AVATAR,
        entityId: 1,
        contentType: 'image/jpeg',
      });

      expect(result.uploadUrl).toBe('https://storage.example.com/signed-url');
      expect(result.objectKey).toMatch(
        /^users\/1\/avatar\/\d+-[a-f0-9]+\.jpg$/,
      );
      expect(result.expiresIn).toBe(600);
      expect(fileStub.getSignedUrl).toHaveBeenCalledWith(
        expect.objectContaining({
          version: 'v4',
          action: 'write',
          contentType: 'image/jpeg',
        }),
      );
    });

    it('rejects an invalid content type', async () => {
      await expect(
        service.createPresignedUpload({
          target: UploadTarget.USER_AVATAR,
          entityId: 1,
          contentType: 'application/pdf',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects when entity does not exist', async () => {
      prisma.user.findUniqueOrThrow.mockRejectedValue(new Error('Not found'));

      await expect(
        service.createPresignedUpload({
          target: UploadTarget.USER_AVATAR,
          entityId: 999,
          contentType: 'image/jpeg',
        }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('generates correct key prefix for each target', async () => {
      const targets = [
        { target: UploadTarget.USER_AVATAR, prefix: 'users/1/avatar/' },
        { target: UploadTarget.TRIP_COVER, prefix: 'trips/1/cover/' },
        { target: UploadTarget.TRIP_PHOTO, prefix: 'trips/1/photos/' },
        {
          target: UploadTarget.EXPENSE_RECEIPT,
          prefix: 'expenses/1/receipts/',
        },
        {
          target: UploadTarget.MARKET_ITEM_IMAGE,
          prefix: 'marketplace/1/images/',
        },
      ];

      for (const { target, prefix } of targets) {
        const result = await service.createPresignedUpload({
          target,
          entityId: 1,
          contentType: 'image/png',
        });
        expect(result.objectKey).toContain(prefix);
        expect(result.objectKey).toMatch(/\.png$/);
      }
    });

    it('rejects market item image upload when listing does not exist', async () => {
      prisma.marketplaceListing.findUniqueOrThrow.mockRejectedValue(
        new Error('Not found'),
      );

      await expect(
        service.createPresignedUpload({
          target: UploadTarget.MARKET_ITEM_IMAGE,
          entityId: 999,
          contentType: 'image/jpeg',
        }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('confirmUpload', () => {
    it('rejects when object key does not match expected prefix', async () => {
      await expect(
        service.confirmUpload(
          {
            target: UploadTarget.USER_AVATAR,
            entityId: 1,
            objectKey: 'trips/1/cover/bad-key.jpg',
          },
          1,
        ),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects when object does not exist in GCS', async () => {
      fileStub.exists.mockResolvedValueOnce([false]);

      await expect(
        service.confirmUpload(
          {
            target: UploadTarget.USER_AVATAR,
            entityId: 1,
            objectKey: 'users/1/avatar/12345-abc123.jpg',
          },
          1,
        ),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('updates user avatar on confirm', async () => {
      const objectKey = 'users/1/avatar/12345-abc123.jpg';
      const result = await service.confirmUpload(
        {
          target: UploadTarget.USER_AVATAR,
          entityId: 1,
          objectKey,
        },
        1,
      );

      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: 1 },
        data: { avatarUrl: objectKey },
      });
      expect(result.objectKey).toBe(objectKey);
      expect(result.url).toBeDefined();
    });

    it('creates trip photo on confirm', async () => {
      const objectKey = 'trips/5/photos/12345-abc123.jpg';
      await service.confirmUpload(
        {
          target: UploadTarget.TRIP_PHOTO,
          entityId: 5,
          objectKey,
          caption: 'Sunset at the beach',
        },
        42,
      );

      expect(prisma.tripPhoto.create).toHaveBeenCalledWith({
        data: {
          tripId: 5,
          uploadedById: 42,
          photoUrl: objectKey,
          caption: 'Sunset at the beach',
        },
      });
    });

    it('deletes old object when replacing avatar', async () => {
      prisma.user.findUnique.mockResolvedValue({
        avatarUrl: 'users/1/avatar/old-key.jpg',
      });

      await service.confirmUpload(
        {
          target: UploadTarget.USER_AVATAR,
          entityId: 1,
          objectKey: 'users/1/avatar/12345-new.jpg',
        },
        1,
      );

      expect(prisma.user.update).toHaveBeenCalled();
      // delete called twice: once for the old original and once for its
      // .thumb.webp sibling.
      expect(fileStub.delete).toHaveBeenCalledTimes(2);
      expect(fileStub.delete).toHaveBeenCalledWith({ ignoreNotFound: true });
    });
  });

  describe('getSignedDownloadUrl', () => {
    it('returns a download URL with expiry', async () => {
      const result = await service.getSignedDownloadUrl(
        'users/1/avatar/test.jpg',
      );

      expect(result.url).toBe('https://storage.example.com/signed-url');
      expect(result.expiresIn).toBe(3600);
      expect(fileStub.getSignedUrl).toHaveBeenCalledWith(
        expect.objectContaining({ version: 'v4', action: 'read' }),
      );
    });
  });

  describe('extractObjectKey', () => {
    it('returns the value unchanged for a bare object key', () => {
      expect(service.extractObjectKey('users/1/avatar/foo.jpg')).toBe(
        'users/1/avatar/foo.jpg',
      );
    });

    it('strips the GCS path-style host', () => {
      expect(
        service.extractObjectKey(
          'https://storage.googleapis.com/oneplan-media/users/1/avatar/foo.jpg',
        ),
      ).toBe('users/1/avatar/foo.jpg');
    });

    it('strips the GCS virtual-hosted form', () => {
      expect(
        service.extractObjectKey(
          'https://oneplan-media.storage.googleapis.com/users/1/avatar/foo.jpg',
        ),
      ).toBe('users/1/avatar/foo.jpg');
    });

    it('strips a legacy Supabase URL for backwards compat', () => {
      expect(
        service.extractObjectKey(
          'https://abc.supabase.co/storage/v1/s3/oneplan-media/users/1/avatar/foo.jpg',
        ),
      ).toBe('users/1/avatar/foo.jpg');
    });

    it('leaves unrelated URLs untouched', () => {
      expect(service.extractObjectKey('https://example.com/foo.jpg')).toBe(
        'https://example.com/foo.jpg',
      );
    });
  });
});
