import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { InviteStatus } from '@prisma/client';
import { PrismaService } from '../../src/prisma/prisma.service';
import { StorageService } from '../../src/storage/storage.service';
import { TripPhotosService } from '../../src/trip-photos/trip-photos.service';

describe('TripPhotosService', () => {
  let service: TripPhotosService;
  let prisma: Record<string, any>;
  let storageService: Record<string, any>;

  const mockAcceptedMember = {
    id: 1,
    tripId: 1,
    userId: 1,
    inviteStatus: InviteStatus.ACCEPTED,
    joinedAt: new Date(),
  };

  const mockPhoto = {
    id: 10,
    tripId: 1,
    uploadedById: 1,
    photoUrl: 'trips/1/photos/abc123.jpg',
    caption: 'Beach sunset',
    createdAt: new Date('2026-03-19'),
    updatedAt: new Date('2026-03-19'),
  };

  const mockPhotoWithUploader = {
    ...mockPhoto,
    uploadedBy: {
      id: 1,
      displayName: 'User One',
      avatarUrl: null,
    },
  };

  const mockSignedUrl = {
    url: 'https://storage.example.com/signed-url',
    expiresIn: 3600,
  };

  beforeEach(() => {
    prisma = {
      tripMember: {
        findUnique: jest.fn(),
      },
      tripPhoto: {
        findMany: jest.fn(),
        findUnique: jest.fn(),
        findUniqueOrThrow: jest.fn(),
        delete: jest.fn(),
      },
      trip: {
        findUniqueOrThrow: jest.fn(),
      },
    };

    storageService = {
      getSignedThumbUrl: jest.fn().mockResolvedValue(mockSignedUrl),
      deleteObject: jest.fn().mockResolvedValue(undefined),
    };

    service = new TripPhotosService(
      prisma as unknown as PrismaService,
      storageService as unknown as StorageService,
    );
  });

  describe('listPhotos', () => {
    it('should return paginated photos with presigned URLs', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findMany.mockResolvedValue([mockPhotoWithUploader]);

      const result = await service.listPhotos(1, 1);

      expect(prisma.tripMember.findUnique).toHaveBeenCalledWith({
        where: { tripId_userId: { tripId: 1, userId: 1 } },
      });
      expect(prisma.tripPhoto.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { tripId: 1 },
          orderBy: { id: 'desc' },
          take: 21,
        }),
      );
      expect(storageService.getSignedThumbUrl).toHaveBeenCalledWith(
        'trips/1/photos/abc123.jpg',
      );
      expect(result.data).toHaveLength(1);
      expect(result.data[0].url).toBe('https://storage.example.com/signed-url');
      expect(result.data[0].uploaderDisplayName).toBe('User One');
      expect(result.data[0].uploaderAvatarUrl).toBeNull();
      expect(result.nextCursor).toBeNull();
    });

    it('should sign uploader avatar when avatar is a storage object key', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findMany.mockResolvedValue([
        {
          ...mockPhotoWithUploader,
          uploadedBy: {
            ...mockPhotoWithUploader.uploadedBy,
            avatarUrl: 'users/1/avatar/avatar.jpg',
          },
        },
      ]);
      storageService.getSignedThumbUrl.mockImplementation(
        async (value: string) => {
          if (value === mockPhoto.photoUrl) {
            return {
              url: 'https://storage.example.com/signed-photo',
              expiresIn: 3600,
            };
          }
          if (value === 'users/1/avatar/avatar.jpg') {
            return {
              url: 'https://storage.example.com/signed-avatar',
              expiresIn: 3600,
            };
          }
          throw new Error(`Unexpected key: ${value}`);
        },
      );

      const result = await service.listPhotos(1, 1);

      expect(result.data[0].url).toBe(
        'https://storage.example.com/signed-photo',
      );
      expect(result.data[0].uploaderAvatarUrl).toBe(
        'https://storage.example.com/signed-avatar',
      );
      expect(storageService.getSignedThumbUrl).toHaveBeenCalledWith(
        'users/1/avatar/avatar.jpg',
      );
    });

    it('should pass through absolute uploader avatar URL', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findMany.mockResolvedValue([
        {
          ...mockPhotoWithUploader,
          uploadedBy: {
            ...mockPhotoWithUploader.uploadedBy,
            avatarUrl: 'https://cdn.example.com/avatar.jpg',
          },
        },
      ]);

      const result = await service.listPhotos(1, 1);

      expect(result.data[0].uploaderAvatarUrl).toBe(
        'https://cdn.example.com/avatar.jpg',
      );
      expect(storageService.getSignedThumbUrl).toHaveBeenCalledTimes(1);
      expect(storageService.getSignedThumbUrl).toHaveBeenCalledWith(
        mockPhoto.photoUrl,
      );
    });

    it('should return nextCursor when more results exist', async () => {
      const photos = Array.from({ length: 21 }, (_, i) => ({
        ...mockPhotoWithUploader,
        id: 100 - i,
      }));
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findMany.mockResolvedValue(photos);

      const result = await service.listPhotos(1, 1);

      expect(result.data).toHaveLength(20);
      expect(result.nextCursor).toBe(81);
    });

    it('should pass cursor to prisma when provided', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findMany.mockResolvedValue([]);

      await service.listPhotos(1, 1, 50);

      expect(prisma.tripPhoto.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          skip: 1,
          cursor: { id: 50 },
        }),
      );
    });

    it('should use custom take value', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findMany.mockResolvedValue([]);

      await service.listPhotos(1, 1, undefined, 10);

      expect(prisma.tripPhoto.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          take: 11,
        }),
      );
    });

    it('should throw ForbiddenException when user is not a member', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(null);

      await expect(service.listPhotos(1, 99)).rejects.toThrow(
        ForbiddenException,
      );
    });
  });

  describe('getPhoto', () => {
    it('should return a photo with presigned URL', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findUnique.mockResolvedValue(mockPhoto);
      prisma.tripPhoto.findUniqueOrThrow.mockResolvedValue(
        mockPhotoWithUploader,
      );

      const result = await service.getPhoto(1, 10, 1);

      expect(result.id).toBe(10);
      expect(result.url).toBe('https://storage.example.com/signed-url');
      expect(result.caption).toBe('Beach sunset');
      expect(result.uploaderDisplayName).toBe('User One');
      expect(result.uploaderAvatarUrl).toBeNull();
    });

    it('should throw NotFoundException when photo does not belong to trip', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findUnique.mockResolvedValue({
        ...mockPhoto,
        tripId: 999,
      });

      await expect(service.getPhoto(1, 10, 1)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should throw NotFoundException when photo does not exist', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findUnique.mockResolvedValue(null);

      await expect(service.getPhoto(1, 999, 1)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should throw ForbiddenException when user is not a member', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(null);

      await expect(service.getPhoto(1, 10, 99)).rejects.toThrow(
        ForbiddenException,
      );
    });
  });

  describe('deletePhoto', () => {
    it('should allow the uploader to delete their photo', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findUnique.mockResolvedValue(mockPhoto);
      prisma.tripPhoto.delete.mockResolvedValue(mockPhoto);

      await service.deletePhoto(1, 10, 1);

      expect(storageService.deleteObject).toHaveBeenCalledWith(
        'trips/1/photos/abc123.jpg',
      );
      expect(prisma.tripPhoto.delete).toHaveBeenCalledWith({
        where: { id: 10 },
      });
    });

    it('should allow the trip owner to delete another users photo', async () => {
      const tripOwnerMember = { ...mockAcceptedMember, userId: 2 };
      const photoByUser1 = { ...mockPhoto, uploadedById: 1 };

      prisma.tripMember.findUnique.mockResolvedValue(tripOwnerMember);
      prisma.tripPhoto.findUnique.mockResolvedValue(photoByUser1);
      prisma.trip.findUniqueOrThrow.mockResolvedValue({ createdById: 2 });
      prisma.tripPhoto.delete.mockResolvedValue(photoByUser1);

      await service.deletePhoto(1, 10, 2);

      expect(storageService.deleteObject).toHaveBeenCalledWith(
        'trips/1/photos/abc123.jpg',
      );
      expect(prisma.tripPhoto.delete).toHaveBeenCalledWith({
        where: { id: 10 },
      });
    });

    it('should throw ForbiddenException when non-uploader non-owner tries to delete', async () => {
      const otherMember = { ...mockAcceptedMember, userId: 3 };
      const photoByUser1 = { ...mockPhoto, uploadedById: 1 };

      prisma.tripMember.findUnique.mockResolvedValue(otherMember);
      prisma.tripPhoto.findUnique.mockResolvedValue(photoByUser1);
      prisma.trip.findUniqueOrThrow.mockResolvedValue({ createdById: 2 });

      await expect(service.deletePhoto(1, 10, 3)).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('should throw NotFoundException when photo does not belong to trip', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(mockAcceptedMember);
      prisma.tripPhoto.findUnique.mockResolvedValue({
        ...mockPhoto,
        tripId: 999,
      });

      await expect(service.deletePhoto(1, 10, 1)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should throw ForbiddenException when user is not a member', async () => {
      prisma.tripMember.findUnique.mockResolvedValue(null);

      await expect(service.deletePhoto(1, 10, 99)).rejects.toThrow(
        ForbiddenException,
      );
    });
  });
});
