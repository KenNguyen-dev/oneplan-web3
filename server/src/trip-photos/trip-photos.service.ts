import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InviteStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { TripPhotoDto } from './dto/trip-photo.dto';
import { TripPhotoListDto } from './dto/trip-photo-list.dto';

const DEFAULT_TAKE = 20;

const PHOTO_INCLUDE = {
  uploadedBy: {
    select: { id: true, displayName: true, avatarUrl: true },
  },
} as const;

type PhotoWithUploader = {
  id: number;
  tripId: number;
  photoUrl: string;
  caption: string | null;
  uploadedById: number;
  createdAt: Date | null;
  uploadedBy: { id: number; displayName: string; avatarUrl: string | null };
};

@Injectable()
export class TripPhotosService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storageService: StorageService,
  ) {}

  async listPhotos(
    tripId: number,
    userId: number,
    cursor?: number,
    take?: number,
  ): Promise<TripPhotoListDto> {
    await this.assertMember(tripId, userId);

    const limit = take ?? DEFAULT_TAKE;

    const photos = await this.prisma.tripPhoto.findMany({
      where: { tripId },
      include: PHOTO_INCLUDE,
      orderBy: { id: 'desc' },
      take: limit + 1,
      ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}),
    });

    const hasMore = photos.length > limit;
    const results = hasMore ? photos.slice(0, limit) : photos;
    const nextCursor = hasMore ? results[results.length - 1].id : null;

    const data = await Promise.all(
      results.map((photo) => this.formatPhoto(photo)),
    );

    return { data, nextCursor };
  }

  async getPhoto(
    tripId: number,
    photoId: number,
    userId: number,
  ): Promise<TripPhotoDto> {
    await this.assertMember(tripId, userId);
    const photo = await this.assertPhotoBelongsToTrip(photoId, tripId);

    const fullPhoto = await this.prisma.tripPhoto.findUniqueOrThrow({
      where: { id: photo.id },
      include: PHOTO_INCLUDE,
    });

    return this.formatPhoto(fullPhoto);
  }

  async deletePhoto(
    tripId: number,
    photoId: number,
    userId: number,
  ): Promise<void> {
    await this.assertMember(tripId, userId);
    const photo = await this.assertPhotoBelongsToTrip(photoId, tripId);
    await this.assertCanDelete(photo, tripId, userId);

    await this.storageService.deleteObject(photo.photoUrl);
    await this.prisma.tripPhoto.delete({ where: { id: photoId } });
  }

  // ── Private helpers ──────────────────────────────────────────────

  private async assertMember(tripId: number, userId: number): Promise<void> {
    const member = await this.prisma.tripMember.findUnique({
      where: { tripId_userId: { tripId, userId } },
    });

    if (!member || member.inviteStatus !== InviteStatus.ACCEPTED) {
      throw new ForbiddenException('You are not a member of this trip');
    }
  }

  private async assertPhotoBelongsToTrip(
    photoId: number,
    tripId: number,
  ): Promise<{
    id: number;
    tripId: number;
    uploadedById: number;
    photoUrl: string;
  }> {
    const photo = await this.prisma.tripPhoto.findUnique({
      where: { id: photoId },
    });

    if (!photo || photo.tripId !== tripId) {
      throw new NotFoundException('Photo not found');
    }

    return photo;
  }

  private async assertCanDelete(
    photo: { uploadedById: number },
    tripId: number,
    userId: number,
  ): Promise<void> {
    if (photo.uploadedById === userId) return;

    const trip = await this.prisma.trip.findUniqueOrThrow({
      where: { id: tripId },
      select: { createdById: true },
    });

    if (trip.createdById === userId) return;

    throw new ForbiddenException(
      'Only the uploader or trip owner can delete this photo',
    );
  }

  private async formatPhoto(photo: PhotoWithUploader): Promise<TripPhotoDto> {
    const { url } = await this.storageService.getSignedThumbUrl(photo.photoUrl);
    const uploaderAvatarUrl = await this.resolveMediaUrlOrPassThrough(
      photo.uploadedBy.avatarUrl,
    );

    return {
      id: photo.id,
      tripId: photo.tripId,
      url,
      caption: photo.caption,
      uploadedById: photo.uploadedBy.id,
      uploaderDisplayName: photo.uploadedBy.displayName,
      uploaderAvatarUrl,
      createdAt: photo.createdAt?.toISOString() ?? new Date().toISOString(),
    };
  }

  private async resolveMediaUrlOrPassThrough(
    value: string | null,
  ): Promise<string | null> {
    if (!value) return null;
    if (/^https?:\/\//i.test(value)) return value;

    try {
      const { url } = await this.storageService.getSignedThumbUrl(value);
      return url;
    } catch {
      return value;
    }
  }
}
