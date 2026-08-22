import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateRecentLocationDto } from './dto/create-recent-location.dto';
import { RecentLocationDto } from './dto/recent-location.dto';

@Injectable()
export class RecentLocationsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(userId: number, limit: number): Promise<RecentLocationDto[]> {
    const locations = await this.prisma.recentLocation.findMany({
      where: { userId },
      orderBy: { lastViewedAt: 'desc' },
      take: limit,
    });

    return locations.map((loc) => this.formatLocation(loc));
  }

  async save(
    userId: number,
    dto: CreateRecentLocationDto,
  ): Promise<RecentLocationDto> {
    const address = dto.address ?? '';

    const location = await this.prisma.recentLocation.upsert({
      where: {
        userId_name_address: { userId, name: dto.name, address },
      },
      update: {
        lastViewedAt: new Date(),
        latitude: dto.latitude,
        longitude: dto.longitude,
        pointOfInterestCategory: dto.pointOfInterestCategory ?? null,
      },
      create: {
        userId,
        name: dto.name,
        address,
        latitude: dto.latitude,
        longitude: dto.longitude,
        pointOfInterestCategory: dto.pointOfInterestCategory ?? null,
      },
    });

    return this.formatLocation(location);
  }

  async delete(userId: number, id: number): Promise<void> {
    const location = await this.prisma.recentLocation.findUnique({
      where: { id },
    });

    if (!location || location.userId !== userId) {
      throw new NotFoundException('Recent location not found');
    }

    await this.prisma.recentLocation.delete({ where: { id } });
  }

  // ── Private helpers ──────────────────────────────────────────────

  private formatLocation(location: {
    id: number;
    name: string;
    address: string;
    latitude: any;
    longitude: any;
    pointOfInterestCategory: string | null;
    lastViewedAt: Date;
  }): RecentLocationDto {
    return {
      id: location.id,
      name: location.name,
      address: location.address || null,
      latitude: location.latitude !== null ? Number(location.latitude) : null,
      longitude:
        location.longitude !== null ? Number(location.longitude) : null,
      pointOfInterestCategory: location.pointOfInterestCategory,
      lastViewedAt: location.lastViewedAt.toISOString(),
    };
  }
}
